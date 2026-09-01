# The legacy "before" estate: 12 real hosts (6 Linux, 6 Windows) that AWS
# Transform migrates. The live fbctf app is separate (environments/demo); the
# full 14-server inventory including both is in ../../inventory.
#
# Everything here is disposable. One destroyable root, no bucket that survives
# destroy, no EIPs, no snapshots, no key pairs. Each host self-terminates after
# var.max_lifetime_minutes.

module "network" {
  source = "../../modules/network"

  name     = "fbctf-estate"
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

resource "aws_route53_zone" "corp" {
  name = "corp.local"

  vpc {
    vpc_id = module.network.vpc_id
  }

  force_destroy = true
}

resource "aws_security_group" "estate" {
  name        = "fbctf-estate-host"
  description = "Estate hosts: all traffic within the estate, egress for provisioning and the discovery agent"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "all traffic between estate hosts (produces the dependency graph)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "distro repos, dl.hhvm.com, discovery service, SSM"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fbctf-estate-host" }
}

resource "aws_iam_role" "host" {
  name = "fbctf-estate-host"

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
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "discovery" {
  count      = var.enable_discovery_agent ? 1 : 0
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationDiscoveryAgentAccess"
}

resource "aws_iam_instance_profile" "host" {
  name = "fbctf-estate-host"
  role = aws_iam_role.host.name
}
