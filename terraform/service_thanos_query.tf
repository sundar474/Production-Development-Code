# ── Thanos Query ──────────────────────────────────────────────────────────────
# Connects to thanos-sidecar which runs inside the prometheus task on port 10901.
# In awsvpc mode every task gets its own ENI/IP, so we resolve the prometheus
# task via service discovery DNS: prometheus.observability.local:10901.

resource "aws_ecs_task_definition" "thanos_query" {
  family                   = "observability-thanos-query"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "1024"
  memory                   = "2048"

  container_definitions = jsonencode([
    {
      name      = "thanos-query"
      image     = "${var.ecr_base}/thanos:latest"
      essential = true

      command = [
        "query",
        "--grpc-address=0.0.0.0:10901",
        "--http-address=0.0.0.0:10902",
        "--endpoint=prometheus.observability.local:10901",
        "--query.replica-label=replica",
      ]

      portMappings = [
        { containerPort = 10901, protocol = "tcp" },
        { containerPort = 10902, protocol = "tcp" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/thanos-query"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "thanos-query"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:10902/-/ready || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "thanos_query" {
  name            = "observability-thanos-query"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.thanos_query.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }


  service_registries {
    registry_arn = aws_service_discovery_service.services["thanos-query"].arn
  }
  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Prometheus task must be up (and thus thanos-sidecar inside it)
  depends_on = [
    aws_ecs_service.prometheus,
    aws_ecs_cluster_capacity_providers.observability,
  ]
}
