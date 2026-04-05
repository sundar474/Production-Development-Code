# EFS mount target so the EC2 instance can reach the filesystem.
# One mount target per AZ is enough for a single-node cluster.

data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_efs_mount_target" "grafana" {
  file_system_id  = var.efs_filesystem_id
  subnet_id       = var.subnet_id
  security_groups = [var.security_group_id]
}
