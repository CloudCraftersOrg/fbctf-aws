# Runs the REAL AWS Transform discovery tool (Linux installer) on one EC2 host,
# pointed at a small Linux fleet plus the live fbctf app. The tool SSHes into
# each server and collects genuine inventory / CPU-RAM-disk metrics / running
# processes / netstat dependencies, then exports discovery_tool_export.zip for
# the migration assessment.
#
# On-demand. ~$0.30/hr (t3.xlarge collector + 6x t3.small). Every host
# self-terminates after var.max_lifetime_minutes. `make destroy ENV=discovery-collector`.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_availability_zones" "available" {
  state = "available"
}


resource "tls_private_key" "discovery" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "discovery" {
  key_name   = "fbctf-discovery"
  public_key = tls_private_key.discovery.public_key_openssh
}

resource "local_file" "discovery_key" {
  content         = tls_private_key.discovery.private_key_pem
  filename        = "${path.module}/fbctf-discovery.pem"
  file_permission = "0600"
}


resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "fbctf-discovery-collector" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "fbctf-discovery-collector" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "fbctf-discovery-collector-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "fbctf-discovery-collector" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


resource "aws_iam_role" "host" {
  name = "fbctf-discovery-host"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  name = "fbctf-discovery-host"
  role = aws_iam_role.host.name
}


locals {
  fleet = {
    "catalog-svc-01"   = { ip = "10.70.1.21", role = "java8", type = "t3.small" }
    "finance-batch-01" = { ip = "10.70.1.22", role = "cobol", type = "t3.small" }
    "cache-01"         = { ip = "10.70.1.31", role = "redis", type = "t3.small" }
    "mq-01"            = { ip = "10.70.1.32", role = "rabbitmq", type = "t3.small" }
    "nfs-01"           = { ip = "10.70.1.33", role = "nfs", type = "t3.small" }
    "ci-01"            = { ip = "10.70.1.41", role = "jenkins", type = "t3.small" }
  }

  fleet_ips  = [for h in local.fleet : h.ip]
  windows_ip = "10.70.1.51"
  all_targets = concat(
    [for name, h in local.fleet : { name = name, ip = h.ip }],
    var.enable_windows ? [{ name = "contoso-sql-01", ip = local.windows_ip }] : [],
    var.discover_fbctf ? [
      { name = "fbctf-demo-app", ip = "10.20.10.104" },
      { name = "fbctf-demo-web", ip = "10.20.11.55" },
    ] : []
  )
}

resource "random_password" "windows" {
  count            = var.enable_windows ? 1 : 0
  length           = 20
  special          = true
  override_special = "!@#$%^*-_=+"
}

data "aws_ami" "windows_sql" {
  count       = var.enable_windows ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-SQL_2022_Express-*"]
  }
}

resource "aws_security_group" "windows" {
  count       = var.enable_windows ? 1 : 0
  name        = "fbctf-discovery-windows"
  description = "Windows target: WinRM from the collector, intra-VPC for netstat"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "WinRM HTTP + HTTPS from the collector"
    from_port       = 5985
    to_port         = 5986
    protocol        = "tcp"
    security_groups = [aws_security_group.collector.id]
  }
  ingress {
    description = "intra-VPC (netstat edges + SQL 1433)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-discovery-windows" }
}

resource "aws_instance" "windows" {
  count = var.enable_windows ? 1 : 0

  ami                    = data.aws_ami.windows_sql[0].id
  instance_type          = var.windows_instance_type
  subnet_id              = aws_subnet.public.id
  private_ip             = local.windows_ip
  vpc_security_group_ids = [aws_security_group.windows[0].id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 80
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/windows-user-data.ps1.tpl", {
    max_minutes    = var.max_lifetime_minutes
    admin_password = random_password.windows[0].result
    peer_ips       = join(",", concat(local.fleet_ips, var.discover_fbctf ? ["10.20.10.104"] : []))
  })

  tags = { Name = "fbctf-discovery-contoso-sql-01" }
}

resource "aws_security_group" "fleet" {
  name        = "fbctf-discovery-fleet"
  description = "Fleet: SSH from the collector, all traffic between fleet nodes for the dependency graph"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from the collector"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.collector.id]
  }
  ingress {
    description = "all traffic between fleet nodes (netstat edges)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-discovery-fleet" }
}

resource "aws_instance" "fleet" {
  for_each = local.fleet

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = each.value.type
  subnet_id              = aws_subnet.public.id
  private_ip             = each.value.ip
  key_name               = aws_key_pair.discovery.key_name
  vpc_security_group_ids = [aws_security_group.fleet.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/fleet-user-data.sh.tpl", {
    hostname    = each.key
    role        = each.value.role
    max_minutes = var.max_lifetime_minutes
    peer_ips    = join(" ", [for ip in local.fleet_ips : ip if ip != each.value.ip])
  })

  tags = { Name = "fbctf-discovery-${each.key}", Role = each.value.role }
}


resource "aws_security_group" "collector" {
  name        = "fbctf-discovery-collector"
  description = "Discovery tool: UI on 5000, egress to the fleet and fbctf on 22"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.ui_allow_cidr != "" ? [var.ui_allow_cidr] : []
    content {
      description = "discovery tool admin UI"
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-discovery-collector" }
}

resource "aws_instance" "collector" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.collector_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.collector.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/collector-user-data.sh.tpl", {
    max_minutes = var.max_lifetime_minutes
    ssh_key_pem = tls_private_key.discovery.private_key_pem
    import_csv = join("\n", concat(
      ["hostname_or_ip,os_credential_name,oracle_credential_name"],
      [for t in local.all_targets : "${t.ip},,"]
    ))
  })

  tags = { Name = "fbctf-discovery-collector" }

  # Disposable host; adding a target must not recycle a running collector.
  lifecycle {
    ignore_changes = [user_data]
  }
}


data "aws_vpc" "fbctf" {
  count = var.discover_fbctf ? 1 : 0
  filter {
    name   = "tag:Name"
    values = ["fbctf-demo"]
  }
}

data "aws_route_table" "fbctf_app" {
  count  = var.discover_fbctf ? 1 : 0
  vpc_id = data.aws_vpc.fbctf[0].id
  filter {
    name   = "tag:Name"
    values = ["fbctf-demo-app"]
  }
}

data "aws_security_group" "fbctf_app" {
  count  = var.discover_fbctf ? 1 : 0
  vpc_id = data.aws_vpc.fbctf[0].id
  filter {
    name   = "group-name"
    values = ["fbctf-demo-app-hhvm"]
  }
}

data "aws_security_group" "fbctf_web" {
  count  = var.discover_fbctf ? 1 : 0
  vpc_id = data.aws_vpc.fbctf[0].id
  filter {
    name   = "group-name"
    values = ["fbctf-demo-web-nginx"]
  }
}

resource "aws_vpc_peering_connection" "fbctf" {
  count       = var.discover_fbctf ? 1 : 0
  vpc_id      = aws_vpc.this.id
  peer_vpc_id = data.aws_vpc.fbctf[0].id
  auto_accept = true
  tags        = { Name = "fbctf-discovery-to-demo" }
}

resource "aws_route" "collector_to_fbctf" {
  count                     = var.discover_fbctf ? 1 : 0
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = data.aws_vpc.fbctf[0].cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.fbctf[0].id
}

resource "aws_route" "fbctf_to_collector" {
  count                     = var.discover_fbctf ? 1 : 0
  route_table_id            = data.aws_route_table.fbctf_app[0].id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.fbctf[0].id
}

resource "aws_security_group_rule" "fbctf_app_ssh" {
  count                    = var.discover_fbctf ? 1 : 0
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.fbctf_app[0].id
  source_security_group_id = aws_security_group.collector.id
  description              = "fbctf-discovery: collector SSH for the AWS Transform discovery tool"
}

resource "aws_security_group_rule" "fbctf_web_ssh" {
  count                    = var.discover_fbctf ? 1 : 0
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.fbctf_web[0].id
  source_security_group_id = aws_security_group.collector.id
  description              = "fbctf-discovery: collector SSH for the AWS Transform discovery tool"
}
