variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "subnet_ids" { type = list(string) }
variable "tags" { type = map(string) }

# Internal NLB — no SG needed for NLB itself (NLBs don't support SGs)
resource "aws_lb" "internal" {
  name               = "${var.project_name}-${var.environment}-obs-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, { Name = "${var.project_name}-${var.environment}-obs-nlb" })
}

# ── Target Groups ─────────────────────────────────────────────────────────────

# OTLP gRPC :4317 → OTel Collector
resource "aws_lb_target_group" "otlp_grpc" {
  name        = "${var.project_name}-${var.environment}-otlp-grpc"
  port        = 4317
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# OTLP HTTP :4318 → OTel Collector
resource "aws_lb_target_group" "otlp_http" {
  name        = "${var.project_name}-${var.environment}-otlp-http"
  port        = 4318
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# Loki :3100
resource "aws_lb_target_group" "loki" {
  name        = "${var.project_name}-${var.environment}-loki"
  port        = 3100
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/ready"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# Tempo :3200
resource "aws_lb_target_group" "tempo" {
  name        = "${var.project_name}-${var.environment}-tempo"
  port        = 3200
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/ready"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# Prometheus :9090
resource "aws_lb_target_group" "prometheus" {
  name        = "${var.project_name}-${var.environment}-prometheus"
  port        = 9090
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/-/healthy"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# Thanos Query :9091
resource "aws_lb_target_group" "thanos_query" {
  name        = "${var.project_name}-${var.environment}-thanos-query"
  port        = 9091
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/-/healthy"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# Grafana :3000
resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-${var.environment}-grafana"
  port        = 3000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/api/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = var.tags
}

# ── Listeners ─────────────────────────────────────────────────────────────────
resource "aws_lb_listener" "otlp_grpc" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 4317
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otlp_grpc.arn
  }
}

resource "aws_lb_listener" "otlp_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 4318
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otlp_http.arn
  }
}

resource "aws_lb_listener" "loki" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 3100
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.loki.arn
  }
}

resource "aws_lb_listener" "tempo" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 3200
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tempo.arn
  }
}

resource "aws_lb_listener" "prometheus" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 9090
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }
}

resource "aws_lb_listener" "thanos_query" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 9091
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.thanos_query.arn
  }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 3000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

output "nlb_arn"        { value = aws_lb.internal.arn }
output "nlb_dns"        { value = aws_lb.internal.dns_name }
output "tg_grpc_arn"    { value = aws_lb_target_group.otlp_grpc.arn }
output "tg_http_arn"    { value = aws_lb_target_group.otlp_http.arn }
output "tg_loki_arn"    { value = aws_lb_target_group.loki.arn }
output "tg_tempo_arn"   { value = aws_lb_target_group.tempo.arn }
output "tg_prom_arn"    { value = aws_lb_target_group.prometheus.arn }
output "tg_thanos_arn"  { value = aws_lb_target_group.thanos_query.arn }
output "tg_grafana_arn" { value = aws_lb_target_group.grafana.arn }
