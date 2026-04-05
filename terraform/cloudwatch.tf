# Pre-create all log groups so the ECS execution role never needs
# logs:CreateLogGroup at runtime (avoids the "log group doesn't exist" error).

locals {
  log_groups = [
    "/ecs/observability/node-exporter",
    "/ecs/observability/prometheus",
    "/ecs/observability/thanos-sidecar",
    "/ecs/observability/loki",
    "/ecs/observability/tempo",
    "/ecs/observability/alloy",
    "/ecs/observability/grafana",
    "/ecs/observability/thanos-query",
  ]
}

resource "aws_cloudwatch_log_group" "observability" {
  for_each          = toset(local.log_groups)
  name              = each.value
  retention_in_days = 30
}
