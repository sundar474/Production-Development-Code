output "cluster_name" {
  value = aws_ecs_cluster.observability.name
}

output "ec2_instance_profile" {
  value = aws_iam_instance_profile.ec2.name
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "verify_services_command" {
  value = <<-CMD
    aws ecs describe-services \
      --cluster ${aws_ecs_cluster.observability.name} \
      --services \
        observability-node-exporter \
        observability-prometheus \
        observability-loki \
        observability-tempo \
        observability-alloy \
        observability-thanos-query \
        observability-grafana \
      --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' \
      --output table
  CMD
}
