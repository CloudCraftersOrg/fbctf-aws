# Network for the fbctf demo: 1 VPC, 2 AZs, three subnet tiers, single NAT.
# Thin wrapper around terraform-aws-modules/vpc (see requirements doc §3.1).
#   - public:        ALB + NAT gateway
#   - private (app): nginx tier + HHVM tier
#   - database:      RDS + ElastiCache (both subnet groups built from these)

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 10 + i)]
  data_subnets    = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 20 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.data_subnets

  # RDS subnet group now; the ElastiCache subnet group is created in the cache
  # module (Phase 4) from the same database subnets.
  create_database_subnet_group = true
  database_subnet_group_name   = "${var.name}-db"

  enable_dns_support   = true
  enable_dns_hostnames = true

  # Single NAT: demo cost tradeoff — one shared private route table.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  public_subnet_suffix   = "public"
  private_subnet_suffix  = "app"
  database_subnet_suffix = "data"
}
