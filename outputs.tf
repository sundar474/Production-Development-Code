output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.observability.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.observability.arn
}

output "nlb_dns_name" {
  description = "Internal NLB DNS name — used by services to communicate"
  value       = module.nlb.nlb_dns
}

output "s3_bucket_name" {
  description = "S3 bucket for Loki / Tempo / Thanos"
  value       = module.s3.bucket_id
}

output "efs_id" {
  description = "EFS file system ID for Grafana dashboards"
  value       = module.efs.efs_id
}

output "grafana_service_name" {
  value = module.grafana.service_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs — push images to these before deploying"
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  value = local.vpc_id
}
