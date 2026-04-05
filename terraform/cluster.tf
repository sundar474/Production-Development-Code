# ── ECS Cluster ────────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "observability" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ── ECS Capacity Provider (links cluster → ASG) ────────────────────────────────
resource "aws_ecs_capacity_provider" "ec2" {
  name = "observability-ec2-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "observability" {
  cluster_name       = aws_ecs_cluster.observability.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 1
  }
}

# ── EC2 Instance Profile ───────────────────────────────────────────────────────
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance" {
  name               = "observability-ecs-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ec2_ecs" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "observability-ecs-ec2-profile"
  role = aws_iam_role.ec2_instance.name
}

# ── Latest ECS-optimised Amazon Linux 2 AMI ───────────────────────────────────
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# ── Launch Template ────────────────────────────────────────────────────────────
resource "aws_launch_template" "ecs" {
  name_prefix   = "observability-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [var.security_group_id]

  # Register instance with the ECS cluster + prepare host paths
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true   >> /etc/ecs/ecs.config

    # Host directories required by task definitions with host mounts
    mkdir -p /data/prometheus /data/loki /data/tempo
    chmod 777 /data/prometheus /data/loki /data/tempo

    # Mount EFS for Grafana
    yum install -y amazon-efs-utils
    mkdir -p /mnt/efs/grafana
    mount -t efs -o tls ${var.efs_filesystem_id}:/ /mnt/efs
    chmod 777 /mnt/efs/grafana

    # Persist EFS mount across reboots
    echo "${var.efs_filesystem_id}:/ /mnt/efs efs _netdev,tls 0 0" >> /etc/fstab
  EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 60
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "observability-ecs-ec2"
      Project = "observability"
    }
  }
}

# ── Auto Scaling Group ─────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "ecs" {
  name                = "observability-ecs-asg"
  vpc_zone_identifier = [var.subnet_id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "observability-ecs-ec2"
    propagate_at_launch = true
  }

  # Give ECS capacity provider full control over instance lifecycle
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
