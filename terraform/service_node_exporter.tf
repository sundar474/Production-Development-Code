# ── node-exporter ─────────────────────────────────────────────────────────────
# Uses host networking (networkMode=host) so it can see real host metrics.
# Must NOT have awsvpc network_configuration or service_registries on the service.
# node-exporter binds to the host IP directly on port 9100, so Prometheus
# can reach it via the EC2 private IP (resolved by its Cloud Map A-record).

resource "aws_ecs_task_definition" "node_exporter" {
  family                   = "observability-node-exporter"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "256"
  memory                   = "512"

  pid_mode = "host"

  volume {
    name      = "proc"
    host_path = "/proc"
  }
  volume {
    name      = "sys"
    host_path = "/sys"
  }
  volume {
    name      = "root"
    host_path = "/"
  }

  container_definitions = jsonencode([
    {
      name      = "node-exporter"
      image     = "${var.ecr_base}/node-exporter:latest"
      essential = true

      portMappings = [
        { containerPort = 9100, hostPort = 9100, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = "proc", containerPath = "/host/proc", readOnly = true },
        { sourceVolume = "sys",  containerPath = "/host/sys",  readOnly = true },
        { sourceVolume = "root", containerPath = "/rootfs",    readOnly = true },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/node-exporter"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "node-exporter"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9100/metrics || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "node_exporter" {
  name            = "observability-node-exporter"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.node_exporter.arn
  desired_count   = 1
  launch_type     = "EC2"

  # host networking — no network_configuration, no service_registries
  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_ecs_cluster_capacity_providers.observability]
}
