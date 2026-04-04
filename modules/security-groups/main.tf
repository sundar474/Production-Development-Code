variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "tags" { type = map(string) }

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# ── ECS EC2 Instance SG ───────────────────────────────────────────────────────
resource "aws_security_group" "ecs_instance" {
  name        = "${local.prefix}-ecs-instance-sg"
  description = "ECS EC2 instance security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Node exporter from within VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "All traffic within SG (ECS task to task)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-ecs-instance-sg" })
}

# ── NLB SG ────────────────────────────────────────────────────────────────────
resource "aws_security_group" "nlb" {
  name        = "${local.prefix}-nlb-sg"
  description = "Internal NLB - OTLP gRPC and HTTP"
  vpc_id      = var.vpc_id

  ingress {
    description = "OTLP gRPC"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description = "OTLP HTTP"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-nlb-sg" })
}

# ── OTel Collector SG ─────────────────────────────────────────────────────────
resource "aws_security_group" "otel_collector" {
  name        = "${local.prefix}-otel-collector-sg"
  description = "OTel Collector Gateway"
  vpc_id      = var.vpc_id

  ingress {
    description     = "OTLP gRPC from NLB"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description     = "OTLP HTTP from NLB"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description = "Health check"
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-otel-collector-sg" })
}

# ── Grafana Alloy SG ──────────────────────────────────────────────────────────
resource "aws_security_group" "alloy" {
  name        = "${local.prefix}-alloy-sg"
  description = "Grafana Alloy agents"
  vpc_id      = var.vpc_id

  ingress {
    description     = "OTLP gRPC from OTel Collector"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.otel_collector.id]
  }

  ingress {
    description = "Alloy UI"
    from_port   = 12345
    to_port     = 12345
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-alloy-sg" })
}

# ── Loki SG ───────────────────────────────────────────────────────────────────
resource "aws_security_group" "loki" {
  name        = "${local.prefix}-loki-sg"
  description = "Loki write and read"
  vpc_id      = var.vpc_id

  ingress {
    description = "Loki HTTP from Alloy and Grafana"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    security_groups = [
      aws_security_group.alloy.id,
      aws_security_group.grafana.id
    ]
  }

  ingress {
    description = "Loki gossip"
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-loki-sg" })
}

# ── Tempo SG ──────────────────────────────────────────────────────────────────
resource "aws_security_group" "tempo" {
  name        = "${local.prefix}-tempo-sg"
  description = "Grafana Tempo"
  vpc_id      = var.vpc_id

  ingress {
    description     = "OTLP gRPC traces from Alloy"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id]
  }

  ingress {
    description     = "Tempo HTTP query from Grafana"
    from_port       = 3200
    to_port         = 3200
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-tempo-sg" })
}

# ── Prometheus SG ─────────────────────────────────────────────────────────────
resource "aws_security_group" "prometheus" {
  name        = "${local.prefix}-prometheus-sg"
  description = "Prometheus + Thanos sidecar"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Prometheus HTTP from Alloy remote-write"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id]
  }

  ingress {
    description     = "Thanos sidecar gRPC"
    from_port       = 10901
    to_port         = 10901
    protocol        = "tcp"
    security_groups = [aws_security_group.thanos.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-prometheus-sg" })
}

# ── Thanos SG ─────────────────────────────────────────────────────────────────
resource "aws_security_group" "thanos" {
  name        = "${local.prefix}-thanos-sg"
  description = "Thanos Query and Compactor"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Thanos Query HTTP from Grafana"
    from_port       = 9091
    to_port         = 9091
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  ingress {
    description = "Thanos internal gRPC"
    from_port   = 10901
    to_port     = 10902
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-thanos-sg" })
}

# ── Grafana SG ────────────────────────────────────────────────────────────────
resource "aws_security_group" "grafana" {
  name        = "${local.prefix}-grafana-sg"
  description = "Grafana dashboard"
  vpc_id      = var.vpc_id

  ingress {
    description = "Grafana UI from everywhere (restrict to your IP in prod)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-grafana-sg" })
}

# ── EFS SG ────────────────────────────────────────────────────────────────────
resource "aws_security_group" "efs" {
  name        = "${local.prefix}-efs-sg"
  description = "EFS mount targets for Grafana"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from Grafana task"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.prefix}-efs-sg" })
}

output "ecs_instance_sg_id"   { value = aws_security_group.ecs_instance.id }
output "nlb_sg_id"            { value = aws_security_group.nlb.id }
output "otel_collector_sg_id" { value = aws_security_group.otel_collector.id }
output "alloy_sg_id"          { value = aws_security_group.alloy.id }
output "loki_sg_id"           { value = aws_security_group.loki.id }
output "tempo_sg_id"          { value = aws_security_group.tempo.id }
output "prometheus_sg_id"     { value = aws_security_group.prometheus.id }
output "thanos_sg_id"         { value = aws_security_group.thanos.id }
output "grafana_sg_id"        { value = aws_security_group.grafana.id }
output "efs_sg_id"            { value = aws_security_group.efs.id }
