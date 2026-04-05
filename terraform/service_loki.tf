# ── Loki ──────────────────────────────────────────────────────────────────────
# S3 backend for chunks; /data/loki on host for index/cache/WAL.
# Config is baked into the Docker image via the Dockerfile COPY.

resource "aws_ecs_task_definition" "loki" {
  family                   = "observability-loki"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "512"
  memory                   = "2048"

  volume {
    name      = "loki-data"
    host_path = "/data/loki"
  }

  container_definitions = jsonencode([
    {
      name      = "loki"
      image     = "${var.ecr_base}/loki:latest"
      essential = true

      # Config baked in image; expand-env picks up AWS_REGION + S3_BUCKET
      command = ["-config.file=/etc/loki/config.yml", "-config.expand-env=true"]

      portMappings = [
        { containerPort = 3100, protocol = "tcp" },
        { containerPort = 9095, protocol = "tcp" },
      ]

      mountPoints = [
        { sourceVolume = "loki-data", containerPath = "/loki", readOnly = false }
      ]

      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "S3_BUCKET",  value = var.s3_bucket  },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/loki"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "loki"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 90
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "loki" {
  name            = "observability-loki"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }


  service_registries {
    registry_arn = aws_service_discovery_service.services["loki"].arn
  }
  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_ecs_cluster_capacity_providers.observability]
}
