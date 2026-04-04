variable "project_name" {}
variable "environment" {}
variable "service_name" {}
variable "cluster_id" {}
variable "task_role_arn" {}
variable "exec_role_arn" {}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "desired_count" { type = number }
variable "cpu" { type = number }
variable "memory" { type = number }
variable "image_uri" {}
variable "container_port" { type = number }
variable "aws_region" {}
variable "s3_bucket_id" {}
variable "environment_vars" { type = map(string), default = {} }
variable "tags" { type = map(string) }

# Optional EFS — only used by Grafana
variable "efs_file_system_id" { default = "" }
variable "efs_access_point_id" { default = "" }

# Optional NLB target group ARNs — only used by OTel Collector
variable "nlb_target_group_grpc_arn" { default = "" }
variable "nlb_target_group_http_arn" { default = "" }

locals {
  log_group    = "/ecs/${var.project_name}-${var.environment}/${var.service_name}"
  has_efs      = var.efs_file_system_id != ""
  has_nlb_grpc = var.nlb_target_group_grpc_arn != ""
  has_nlb_http = var.nlb_target_group_http_arn != ""

  container_env = [
    for k, v in var.environment_vars : { name = k, value = v }
  ]
}

resource "aws_cloudwatch_log_group" "service" {
  name              = local.log_group
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_ecs_task_definition" "service" {
  family                   = "${var.project_name}-${var.environment}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.exec_role_arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.image_uri
      essential = true
      cpu       = var.cpu
      memory    = var.memory

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = local.container_env

      mountPoints = local.has_efs ? [
        {
          sourceVolume  = "efs-grafana"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "echo ok || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  dynamic "volume" {
    for_each = local.has_efs ? [1] : []
    content {
      name = "efs-grafana"
      efs_volume_configuration {
        file_system_id          = var.efs_file_system_id
        root_directory          = "/"
        transit_encryption      = "ENABLED"
        transit_encryption_port = 2049
        authorization_config {
          access_point_id = var.efs_access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "service" {
  name                               = "${var.project_name}-${var.environment}-${var.service_name}"
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.service.arn
  desired_count                      = var.desired_count
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 0
  }

  # Use EC2 capacity provider — set in cluster
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  dynamic "load_balancer" {
    for_each = local.has_nlb_grpc ? [1] : []
    content {
      target_group_arn = var.nlb_target_group_grpc_arn
      container_name   = var.service_name
      container_port   = 4317
    }
  }

  dynamic "load_balancer" {
    for_each = local.has_nlb_http ? [1] : []
    content {
      target_group_arn = var.nlb_target_group_http_arn
      container_name   = var.service_name
      container_port   = 4318
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

output "service_name"        { value = aws_ecs_service.service.name }
output "service_id"          { value = aws_ecs_service.service.id }
output "task_definition_arn" { value = aws_ecs_task_definition.service.arn }
