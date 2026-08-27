# Reusable EC2 tier: launch template + ASG on the frozen Xenial AMI.
# Instantiated twice — app (HHVM, Phase 5) and web (nginx, Phase 6) — with
# different user-data (rendered by the caller via templatefile()).

data "aws_ami" "xenial" {
  most_recent = true
  owners      = ["099720109477"]

  # Canonical deprecated these AMIs in 2023 — without include_deprecated the
  # data source finds nothing (validated us-east-1: ami-0b0ea68c435eb488d).
  include_deprecated = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_launch_template" "this" {
  name          = var.name
  image_id      = data.aws_ami.xenial.id
  instance_type = var.instance_type

  update_default_version = true

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(var.user_data)

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = var.name
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                = var.name
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids

  target_group_arns = var.target_group_arns

  # ELB health with a generous grace period: boot-time provisioning takes
  # minutes even from the prebuilt tarball (§4 risk 4).
  health_check_type         = length(var.target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }
}
