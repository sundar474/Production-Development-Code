# ── Grafana ───────────────────────────────────────────────────────────────────
# Datasource provisioning is baked into the image.
# Dashboards/plugins persist on host at /data/grafana.

resource "aws_ecs_task_definition" "grafana" {
  family                   = "observability-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "512"
  memory                   = "512"

  volume {
    name      = "grafana-data"
    host_path = "/data/grafana"
  }

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "${var.ecr_base}/grafana:latest"
      essential = true

      portMappings = [
        { containerPort = 3000, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = "grafana-data", containerPath = "/var/lib/grafana", readOnly = false }
      ]

      environment = [
        { name = "GF_SECURITY_ADMIN_USER",     value = "admin"         },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = "changeme"      },
        { name = "GF_AUTH_ANONYMOUS_ENABLED",  value = "false"         },
        { name = "GF_SERVER_ROOT_URL",         value = "http://grafana.observability.local:3000" },
        { name = "GF_FEATURE_TOGGLES_ENABLE",  value = "traceqlEditor" },
        { name = "GF_UPDATES_CHECK_FOR_UPDATES",        value = "false" },
        { name = "GF_ANALYTICS_CHECK_FOR_UPDATES",      value = "false" },
        { name = "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES", value = "false" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/grafana"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "grafana"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "grafana" {
  name            = "observability-grafana"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["grafana"].arn
  }

  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [
    aws_ecs_service.alloy,
    aws_ecs_service.thanos_query,
    aws_ecs_service.loki,
    aws_ecs_service.tempo,
    aws_ecs_cluster_capacity_providers.observability,
  ]
}
