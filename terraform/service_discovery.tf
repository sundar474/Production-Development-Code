# ── Private DNS for inter-service communication ───────────────────────────────
# ECS tasks in awsvpc mode each get their own ENI + private IP.
# They cannot resolve each other by container name (Docker Compose only).
# ECS Service Discovery (Cloud Map) registers each task's IP into Route53
# under observability.local so containers reach each other by DNS name.
#
# Result: loki.observability.local, prometheus.observability.local, etc.

resource "aws_service_discovery_private_dns_namespace" "observability" {
  name        = "observability.local"
  description = "Private DNS for observability ECS services"
  vpc         = var.vpc_id
}

locals {
  # Map of Cloud Map service name → container port used for health-check DNS
  discovery_services = {
    "prometheus"   = 9090
    "loki"         = 3100
    "tempo"        = 3200
    "alloy"        = 12345
    "thanos-query" = 10902
    "grafana"      = 3000
  }
}

resource "aws_service_discovery_service" "services" {
  for_each = local.discovery_services

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.observability.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
