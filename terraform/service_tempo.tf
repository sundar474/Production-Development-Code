# ── Tempo ─────────────────────────────────────────────────────────────────────
# S3 backend for traces; /data/tempo for WAL + generator WAL.
# Config is baked into the image; expand-env handles env-var substitution.

resource "aws_ecs_task_definition" "tempo" {
  family                   = "observability-tempo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "512"
  memory                   = "1536"

  volume {
    name      = "tempo-data"
    host_path = "/data/tempo"
  }

  container_definitions = jsonencode([
    {
      name      = "tempo"
      image     = "${var.ecr_base}/tempo:latest"
      essential = true

      command = ["-config.file=/etc/tempo/config.yml", "-config.expand-env=true"]

      portMappings = [
        { containerPort = 3200, protocol = "tcp" },
        { containerPort = 4317, protocol = "tcp" },
        { containerPort = 4318, protocol = "tcp" },
      ]

      mountPoints = [
        { sourceVolume = "tempo-data", containerPath = "/var/tempo", readOnly = false }
      ]

      environment = [
        { name = "AWS_REGION",                  value = var.aws_region },
        { name = "S3_BUCKET",                   value = var.s3_bucket  },
        # Prometheus remote-write; resolved at runtime via service discovery or DNS
        { name = "PROMETHEUS_REMOTE_WRITE_URL", value = "http://prometheus.observability.local:9090/api/v1/write" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/tempo"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "tempo"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 90
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "tempo" {
  name            = "observability-tempo"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.tempo.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }


  service_registries {
    registry_arn = aws_service_discovery_service.services["tempo"].arn
  }
  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_ecs_cluster_capacity_providers.observability]
}
