# ── Prometheus + Thanos Sidecar ───────────────────────────────────────────────
# Both containers share the same task so they share the prometheus-data volume.
# Thanos sidecar uses dependsOn so it waits for Prometheus to be HEALTHY before
# connecting to http://localhost:9090.
#
# prometheus scrape targets (from prometheus.yml baked in image):
#   node-exporter:9100  loki:3100  tempo:3200  alloy:12345  grafana:3000
# These are ECS service-discovery DNS names — they resolve once each service
# is running on the same VPC / subnet.

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "observability-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  cpu                      = "512"
  memory                   = "1536"

  volume {
    name      = "prometheus-data"
    host_path = "/data/prometheus"
  }

  container_definitions = jsonencode([
    # ── Container 1: prometheus ──────────────────────────────────────────────
    {
      name      = "prometheus"
      image     = "${var.ecr_base}/prometheus:latest"
      essential = true

      # CMD from Dockerfile — all flags already baked in
      portMappings = [
        { containerPort = 9090, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = "prometheus-data", containerPath = "/prometheus", readOnly = false }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/prometheus"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9090/-/ready || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 60
      }
    },

    # ── Container 2: thanos-sidecar ──────────────────────────────────────────
    # essential=false so the task keeps running if the sidecar crashes.
    {
      name      = "thanos-sidecar"
      image     = "${var.ecr_base}/thanos:latest"
      essential = false

      command = [
        "sidecar",
        "--tsdb.path=/prometheus",
        "--prometheus.url=http://localhost:9090",
        "--grpc-address=0.0.0.0:10901",
        "--http-address=0.0.0.0:10902",
        "--objstore.config-file=/etc/thanos/bucket.yml",
      ]

      portMappings = [
        { containerPort = 10901, protocol = "tcp" },
        { containerPort = 10902, protocol = "tcp" },
      ]

      mountPoints = [
        { sourceVolume = "prometheus-data", containerPath = "/prometheus", readOnly = true }
      ]

      environment = [
        { name = "S3_BUCKET",  value = var.s3_bucket  },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      # Wait for prometheus to pass its healthCheck before starting
      dependsOn = [
        { containerName = "prometheus", condition = "HEALTHY" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/observability/thanos-sidecar"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "thanos-sidecar"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:10902/-/ready || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 90
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.observability]
}

resource "aws_ecs_service" "prometheus" {
  name            = "observability-prometheus"
  cluster         = aws_ecs_cluster.observability.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["prometheus"].arn
  }
  scheduling_strategy                = "REPLICA"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Wait for node-exporter to be stable before prometheus service starts
  depends_on = [
    aws_ecs_service.node_exporter,
    aws_ecs_cluster_capacity_providers.observability,
  ]
}
