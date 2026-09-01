# One legacy estate host: a single stable EC2 instance (not an ASG — the
# assessment needs a fixed inventory it can name). IMDSv2 required, EBS
# encrypted, SSM-only access, self-terminating via the caller's user-data.

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name
  user_data              = var.user_data

  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [ami] # frozen/deprecated AMIs get replaced by newer lookups otherwise
  }
}
