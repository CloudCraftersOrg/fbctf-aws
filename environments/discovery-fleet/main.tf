# Throwaway fleet that proves the live discovery path: a handful of Graviton
# nano nodes running the AWS Application Discovery Agent, generating traffic
# among themselves so netstat-based dependency capture has something to report.
#
# Cost control is structural, not procedural:
#   - t4g.nano spot instances (~$0.0013/hr each)
#   - no NAT gateway — nodes sit in a public subnet with a public IP
#   - every node runs `shutdown -h +N` at boot and the launch template sets
#     instance_initiated_shutdown_behavior = "terminate", so the fleet deletes
#     itself after max_lifetime_minutes with or without `terraform destroy`
#
# The rich 14-server picture still comes from ../../inventory (the CSV import).
# This fleet exists only to demo agent-based discovery end to end.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name     = "fbctf-discovery"
  az       = data.aws_availability_zones.available.names[0]
  node_ips = [for i in range(var.node_count) : cidrhost(var.vpc_cidr, 10 + i)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = local.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "node" {
  name        = "${local.name}-node"
  description = "Discovery nodes: intra-fleet traffic for dependency capture, egress for the agent and SSM"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "all traffic between fleet nodes (generates the dependency graph)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "agent egress to Application Discovery Service, SSM and package repos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-node" }
}

resource "aws_iam_role" "node" {
  name = "${local.name}-agent"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "discovery" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationDiscoveryAgentAccess"
}

resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-agent"
  role = aws_iam_role.node.name
}

resource "aws_launch_template" "node" {
  name                                 = local.name
  image_id                             = data.aws_ssm_parameter.al2023_arm64.value
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = "terminate"

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  vpc_security_group_ids = [aws_security_group.node.id]

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "terminate"
      max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
      spot_instance_type             = "one-time"
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-node" }
  }
}

resource "aws_instance" "node" {
  count = var.node_count

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  subnet_id  = aws_subnet.public.id
  private_ip = local.node_ips[count.index]

  user_data = base64encode(templatefile("${path.module}/templates/collector-userdata.sh.tpl", {
    region      = var.region
    peer_ips    = join(" ", [for ip in local.node_ips : ip if ip != local.node_ips[count.index]])
    node_index  = count.index
    max_minutes = var.max_lifetime_minutes
  }))

  tags = {
    Name = "${local.name}-node-${count.index}"
  }
}
