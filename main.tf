terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "observability/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  # Pick first two AZs for AZ-A and AZ-B
  az_a_subnet = local.subnet_ids[0]
  az_b_subnet = local.subnet_ids[1]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── S3 ──────────────────────────────────────────────────────────────────────
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# ── EFS (Grafana dashboards) ─────────────────────────────────────────────────
module "efs" {
  source       = "./modules/efs"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = local.vpc_id
  subnet_ids   = local.subnet_ids
  sg_id        = module.security_groups.efs_sg_id
  tags         = local.common_tags
}

# ── IAM ──────────────────────────────────────────────────────────────────────
module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  environment  = var.environment
  account_id   = local.account_id
  aws_region   = var.aws_region
  s3_bucket_id = module.s3.bucket_id
  tags         = local.common_tags
}

# ── ECR ──────────────────────────────────────────────────────────────────────
module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
  services = [
    "otel-collector",
    "grafana-alloy",
    "loki",
    "tempo",
    "prometheus",
    "thanos",
    "grafana",
    "node-exporter"
  ]
}

# ── Security Groups ───────────────────────────────────────────────────────────
module "security_groups" {
  source       = "./modules/security-groups"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = local.vpc_id
  tags         = local.common_tags
}

# ── Internal NLB ─────────────────────────────────────────────────────────────
module "nlb" {
  source       = "./modules/nlb"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = local.vpc_id
  subnet_ids   = local.subnet_ids
  tags         = local.common_tags
}

# ── ECS Cluster (EC2 type) ────────────────────────────────────────────────────
resource "aws_ecs_cluster" "observability" {
  name = "${var.project_name}-${var.environment}-observability"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "observability" {
  cluster_name       = aws_ecs_cluster.observability.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }
}

# ── Auto Scaling Group for ECS EC2 instances ─────────────────────────────────
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = "${var.project_name}-${var.environment}-ecs-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    arn = module.iam.ec2_instance_profile_arn
  }

  vpc_security_group_ids = [module.security_groups.ecs_instance_sg_id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.observability.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
    echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
  EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 80
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-ecs-ec2" })
  }
}

resource "aws_autoscaling_group" "ecs_ec2" {
  name                = "${var.project_name}-${var.environment}-ecs-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_ec2.arn

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 80
    }
  }

  tags = local.common_tags
}

# ── ECS Services ─────────────────────────────────────────────────────────────

module "otel_collector" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "otel-collector"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.otel_collector_sg_id]
  desired_count      = 2
  cpu                = 1024
  memory             = 2048
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-otel-collector:latest"
  container_port     = 4317
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  nlb_target_group_grpc_arn = module.nlb.tg_grpc_arn
  nlb_target_group_http_arn = module.nlb.tg_http_arn
  environment_vars = {
    LOKI_ENDPOINT   = "http://${module.nlb.nlb_dns}:3100"
    TEMPO_ENDPOINT  = "http://${module.nlb.nlb_dns}:4317"
    PROM_ENDPOINT   = "http://${module.nlb.nlb_dns}:9090"
  }
  tags = local.common_tags
}

module "grafana_alloy_az_a" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "grafana-alloy-az-a"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = [local.az_a_subnet]
  security_group_ids = [module.security_groups.alloy_sg_id]
  desired_count      = 1
  cpu                = 2048
  memory             = 4096
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-grafana-alloy:latest"
  container_port     = 12345
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    LOKI_WRITE_ENDPOINT = "http://${module.nlb.nlb_dns}:3100"
    TEMPO_ENDPOINT      = "http://${module.nlb.nlb_dns}:4317"
    PROM_REMOTE_WRITE   = "http://${module.nlb.nlb_dns}:9090/api/v1/write"
  }
  tags = local.common_tags
}

module "grafana_alloy_az_b" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "grafana-alloy-az-b"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = [local.az_b_subnet]
  security_group_ids = [module.security_groups.alloy_sg_id]
  desired_count      = 1
  cpu                = 2048
  memory             = 4096
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-grafana-alloy:latest"
  container_port     = 12345
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    LOKI_WRITE_ENDPOINT = "http://${module.nlb.nlb_dns}:3100"
    TEMPO_ENDPOINT      = "http://${module.nlb.nlb_dns}:4317"
    PROM_REMOTE_WRITE   = "http://${module.nlb.nlb_dns}:9090/api/v1/write"
  }
  tags = local.common_tags
}

module "loki_write" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "loki-write"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.loki_sg_id]
  desired_count      = 2
  cpu                = 2048
  memory             = 8192
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-loki:latest"
  container_port     = 3100
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    LOKI_TARGET    = "write"
    S3_BUCKET_NAME = module.s3.bucket_id
    S3_REGION      = var.aws_region
  }
  tags = local.common_tags
}

module "loki_read" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "loki-read"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.loki_sg_id]
  desired_count      = 2
  cpu                = 2048
  memory             = 4096
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-loki:latest"
  container_port     = 3100
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    LOKI_TARGET    = "read"
    S3_BUCKET_NAME = module.s3.bucket_id
    S3_REGION      = var.aws_region
  }
  tags = local.common_tags
}

module "tempo" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "tempo"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.tempo_sg_id]
  desired_count      = 1
  cpu                = 2048
  memory             = 4096
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-tempo:latest"
  container_port     = 3200
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    S3_BUCKET_NAME = module.s3.bucket_id
    S3_REGION      = var.aws_region
  }
  tags = local.common_tags
}

module "prometheus" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "prometheus"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.prometheus_sg_id]
  desired_count      = 1
  cpu                = 2048
  memory             = 4096
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-prometheus:latest"
  container_port     = 9090
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    S3_BUCKET_NAME = module.s3.bucket_id
    S3_REGION      = var.aws_region
  }
  tags = local.common_tags
}

module "thanos_query" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "thanos-query"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.thanos_sg_id]
  desired_count      = 1
  cpu                = 1024
  memory             = 2048
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-thanos:latest"
  container_port     = 9091
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    S3_BUCKET_NAME      = module.s3.bucket_id
    S3_REGION           = var.aws_region
    THANOS_TARGET       = "query"
    PROMETHEUS_ENDPOINT = "http://${module.nlb.nlb_dns}:9090"
  }
  tags = local.common_tags
}

module "thanos_compactor" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "thanos-compactor"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.thanos_sg_id]
  desired_count      = 1
  cpu                = 1024
  memory             = 2048
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-thanos:latest"
  container_port     = 10902
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  environment_vars = {
    S3_BUCKET_NAME = module.s3.bucket_id
    S3_REGION      = var.aws_region
    THANOS_TARGET  = "compactor"
  }
  tags = local.common_tags
}

module "grafana" {
  source             = "./modules/ecs-service"
  project_name       = var.project_name
  environment        = var.environment
  service_name       = "grafana"
  cluster_id         = aws_ecs_cluster.observability.id
  task_role_arn      = module.iam.ecs_task_role_arn
  exec_role_arn      = module.iam.ecs_exec_role_arn
  subnet_ids         = local.subnet_ids
  security_group_ids = [module.security_groups.grafana_sg_id]
  desired_count      = 1
  cpu                = 1024
  memory             = 2048
  image_uri          = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-grafana:latest"
  container_port     = 3000
  aws_region         = var.aws_region
  s3_bucket_id       = module.s3.bucket_id
  efs_file_system_id = module.efs.efs_id
  efs_access_point_id = module.efs.access_point_id
  environment_vars = {
    GF_PATHS_PROVISIONING     = "/etc/grafana/provisioning"
    GF_AUTH_ANONYMOUS_ENABLED = "false"
    LOKI_URL                  = "http://${module.nlb.nlb_dns}:3100"
    TEMPO_URL                 = "http://${module.nlb.nlb_dns}:3200"
    THANOS_QUERY_URL          = "http://${module.nlb.nlb_dns}:9091"
  }
  tags = local.common_tags
}

# ── Node Exporter (Daemon Service — one per EC2) ──────────────────────────────
resource "aws_ecs_task_definition" "node_exporter" {
  family                   = "${var.project_name}-${var.environment}-node-exporter"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  task_role_arn            = module.iam.ecs_task_role_arn
  execution_role_arn       = module.iam.ecs_exec_role_arn

  container_definitions = jsonencode([
    {
      name      = "node-exporter"
      image     = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}-${var.environment}-node-exporter:latest"
      essential = true
      portMappings = [
        { containerPort = 9100, hostPort = 9100, protocol = "tcp" }
      ]
      mountPoints = [
        { sourceVolume = "proc", containerPath = "/host/proc", readOnly = true },
        { sourceVolume = "sys", containerPath = "/host/sys", readOnly = true },
        { sourceVolume = "rootfs", containerPath = "/rootfs", readOnly = true }
      ]
      command = [
        "--path.procfs=/host/proc",
        "--path.rootfs=/rootfs",
        "--path.sysfs=/host/sys",
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-${var.environment}/node-exporter"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  volume {
    name      = "proc"
    host_path { path = "/proc" }
  }
  volume {
    name      = "sys"
    host_path { path = "/sys" }
  }
  volume {
    name      = "rootfs"
    host_path { path = "/" }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "node_exporter" {
  name            = "${var.project_name}-${var.environment}-node-exporter"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.node_exporter.arn
  scheduling_strategy = "DAEMON"

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  tags = local.common_tags
}

# ── Thanos Compactor Scheduled Task ──────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "thanos_compactor" {
  name                = "${var.project_name}-${var.environment}-thanos-compactor"
  description         = "Run Thanos Compactor every 2 hours"
  schedule_expression = "rate(2 hours)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "thanos_compactor" {
  rule      = aws_cloudwatch_event_rule.thanos_compactor.name
  target_id = "ThanosCompactor"
  arn       = aws_ecs_cluster.observability.arn
  role_arn  = module.iam.events_role_arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.thanos_compactor.task_definition_arn
    launch_type         = "EC2"

    network_configuration {
      subnets          = local.subnet_ids
      security_groups  = [module.security_groups.thanos_sg_id]
      assign_public_ip = false
    }
  }
}
