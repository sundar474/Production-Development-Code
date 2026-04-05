# ── Alloy ─────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "alloy" {
  family                   = "observability-alloy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "1024"
  memory                   = "2048"

  volume {
    name      = "docker-sock"
    host_path = "/var/run/docker.sock"
  }
  volume {
    name      = "alloy-data"
    host_path = "/data/alloy"
  }

  container_definitions = jsonencode([
    {
      name       = "alloy"
      image      = "${var.ecr_base}/alloy:latest"
      essential  = true
      privileged = true

      command = [
        "run",
        "--server.http.listen-addr=0.0.0.0:12345",
        "--storage.path=/data/alloy",
        "--stability.level=generally-available",
        "/etc/alloy/config.alloy",
      ]

      portMappings = [
        { containerPort = 4317,  protocol = "tcp" },
        { containerPort = 4318,  protocol = "tcp" },
        { containerPort = 12345, protocol = "tcp" },
      ]

      mountPoints = [
        { sourceVolume = "docker-sock", containerPath = "/var/run/docker.sock", readOnly = false },
        { sourceVolume = "alloy-data",  containerPath = "/data/alloy",          readOnly = false },
      ]

      environment = [
        { name = "TEMPO_ENDPOINT",      value = "tempo.observability.local:4317" },
        { name = "PROMETHEUS_ENDPOINT", value = "http://prometheus.observability.local:9090/api/v1/write" },
        { name = "LOKI_ENDPOINT",       value = "http://loki.observability.local:3100/loki/api/v1/push" },
        { name = "NODE_EXPORTER_ADDR",  value = "node-exporter.observability.local:9100" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/alloy"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "alloy"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=3 --timeout=10 --spider http://localhost:12345/-/ready || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 10
        startPeriod = 300
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "alloy" {
  name            = "observability-alloy"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.alloy.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["alloy"].arn
  }

  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [
    aws_ecs_service.loki,
    aws_ecs_service.tempo,
    aws_ecs_service.prometheus,
    aws_ecs_cluster_capacity_providers.observability,
  ]
}
