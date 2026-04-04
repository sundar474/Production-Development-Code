variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "subnet_ids" { type = list(string) }
variable "sg_id" {}
variable "tags" { type = map(string) }

resource "aws_efs_file_system" "grafana" {
  creation_token   = "${var.project_name}-${var.environment}-grafana"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-${var.environment}-grafana-efs" })
}

resource "aws_efs_mount_target" "grafana" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = each.value
  security_groups = [var.sg_id]
}

resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    gid = 472   # grafana default GID
    uid = 472   # grafana default UID
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "755"
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-${var.environment}-grafana-ap" })
}

output "efs_id" {
  value = aws_efs_file_system.grafana.id
}

output "efs_arn" {
  value = aws_efs_file_system.grafana.arn
}

output "access_point_id" {
  value = aws_efs_access_point.grafana.id
}
