# The 12 estate hosts and the dependency edges between them. Everything sits in
# one AZ on purpose (matches the "single-AZ" resilience finding in the
# inventory). IPs are static so corp.local records and the chatter targets can
# be computed without waiting on instance creation.

locals {
  subnet_id = module.network.private_app_subnet_ids[0]

  linux_hosts = {
    "catalog-svc-01"   = { ip = "10.30.10.41", ami = data.aws_ami.rhel7.id, type = "t3.small", role = "java8", root_gb = 30 }
    "finance-batch-01" = { ip = "10.30.10.42", ami = data.aws_ami.rhel8.id, type = "t3.small", role = "cobol", root_gb = 30 }
    "cache-01"         = { ip = "10.30.10.51", ami = data.aws_ami.amazon_linux_2.id, type = "t3.small", role = "redis", root_gb = 30 }
    "mq-01"            = { ip = "10.30.10.52", ami = data.aws_ami.ubuntu_xenial.id, type = "t3.small", role = "rabbitmq", root_gb = 30 }
    "nfs-01"           = { ip = "10.30.10.53", ami = data.aws_ami.amazon_linux_2.id, type = "t3.small", role = "nfs", root_gb = 40 }
    "ci-01"            = { ip = "10.30.10.61", ami = data.aws_ami.amazon_linux_2.id, type = "t3.small", role = "jenkins", root_gb = 30 }
  }

  windows_hosts = {
    "contoso-web-01" = { ip = "10.30.10.11", ami = data.aws_ami.windows_2016.id, type = "t3.small", role = "iis-dotnet", root_gb = 40 }
    "contoso-app-01" = { ip = "10.30.10.21", ami = data.aws_ami.windows_2019.id, type = "t3.small", role = "iis-dotnet", root_gb = 40 }
    "contoso-app-02" = { ip = "10.30.10.22", ami = data.aws_ami.windows_2019.id, type = "t3.small", role = "iis-dotnet", root_gb = 40 }
    # 2016, not fleet.yaml's 2012 R2: AWS no longer publishes the 2012 R2 base AMI.
    "contoso-worker-01" = { ip = "10.30.10.23", ami = data.aws_ami.windows_2016.id, type = "t3.small", role = "worker", root_gb = 40 }
    # SQL Express AMI ships a 75 GB root snapshot - can't go below that.
    "contoso-sql-01"     = { ip = "10.30.10.31", ami = data.aws_ami.windows_2019_sql_express.id, type = "t3.medium", role = "sqlserver", root_gb = 80 }
    "contoso-sql-rpt-01" = { ip = "10.30.10.32", ami = data.aws_ami.windows_2019_sql_express.id, type = "t3.small", role = "sqlserver", root_gb = 80 }
  }

  hosts = merge(local.linux_hosts, var.enable_windows_tier ? local.windows_hosts : {})

  edges = [
    { from = "contoso-web-01", to = "contoso-app-01", port = 443 },
    { from = "contoso-web-01", to = "contoso-app-02", port = 443 },
    { from = "contoso-app-01", to = "contoso-sql-01", port = 1433 },
    { from = "contoso-app-02", to = "contoso-sql-01", port = 1433 },
    { from = "contoso-app-01", to = "cache-01", port = 6379 },
    { from = "contoso-app-02", to = "cache-01", port = 6379 },
    { from = "contoso-app-01", to = "mq-01", port = 5672 },
    { from = "contoso-app-01", to = "catalog-svc-01", port = 8080 },
    { from = "contoso-app-02", to = "catalog-svc-01", port = 8080 },
    { from = "contoso-worker-01", to = "mq-01", port = 5672 },
    { from = "contoso-worker-01", to = "contoso-sql-01", port = 1433 },
    { from = "contoso-sql-01", to = "contoso-sql-rpt-01", port = 1433 },
    { from = "finance-batch-01", to = "nfs-01", port = 2049 },
    { from = "finance-batch-01", to = "contoso-sql-01", port = 1433 },
    { from = "catalog-svc-01", to = "contoso-sql-01", port = 1433 },
    { from = "ci-01", to = "contoso-app-01", port = 5985 },
    { from = "ci-01", to = "catalog-svc-01", port = 22 },
  ]

  host_ip = { for k, h in local.hosts : k => h.ip }

  targets = {
    for k, h in local.hosts : k => [
      for e in local.edges : { ip = local.host_ip[e.to], port = e.port }
      if e.from == k && contains(keys(local.hosts), e.to)
    ]
  }

  listen_ports = {
    for k, h in local.hosts : k => distinct([
      for e in local.edges : e.port
      if e.to == k && contains(keys(local.hosts), e.from)
    ])
  }
}

module "linux_host" {
  source   = "../../modules/estate-host"
  for_each = var.enable_windows_tier ? local.linux_hosts : local.hosts

  name                  = "fbctf-estate-${each.key}"
  ami_id                = each.value.ami
  instance_type         = each.value.type
  subnet_id             = local.subnet_id
  private_ip            = each.value.ip
  security_group_ids    = [aws_security_group.estate.id]
  instance_profile_name = aws_iam_instance_profile.host.name
  root_volume_gb        = each.value.root_gb

  user_data = templatefile("${path.module}/templates/linux-role.sh.tpl", {
    hostname        = each.key
    role            = each.value.role
    max_minutes     = var.max_lifetime_minutes
    install_agent   = var.enable_discovery_agent
    region          = var.region
    listen_ports    = local.listen_ports[each.key]
    chatter_targets = local.targets[each.key]
    hosts_map       = local.host_ip
  })

  tags = { Role = each.value.role, Tier = "linux" }
}

module "windows_host" {
  source   = "../../modules/estate-host"
  for_each = var.enable_windows_tier ? local.windows_hosts : {}

  name                  = "fbctf-estate-${each.key}"
  ami_id                = each.value.ami
  instance_type         = each.value.type
  subnet_id             = local.subnet_id
  private_ip            = each.value.ip
  security_group_ids    = [aws_security_group.estate.id]
  instance_profile_name = aws_iam_instance_profile.host.name
  root_volume_gb        = each.value.root_gb

  user_data = templatefile("${path.module}/templates/windows-role.ps1.tpl", {
    hostname      = each.key
    role          = each.value.role
    max_minutes   = var.max_lifetime_minutes
    install_agent = var.enable_discovery_agent
    region        = var.region
    hosts_map     = local.host_ip
    chatter_literal = join(",", [
      for t in local.targets[each.key] : "@{ip='${t.ip}';port=${t.port}}"
    ])
  })

  tags = { Role = each.value.role, Tier = "windows" }
}
