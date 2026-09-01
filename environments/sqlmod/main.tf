# Live SQL Server for the Transform capability that needs a real database: the
# full agentic SQL Server -> Aurora modernization job. Transform creates its own
# DMS replication instance inside this VPC, connects to the SQL Server, reads the
# schema, converts the stored procs and rewrites the .NET data layer.
#
# SQL Server runs as the official mssql:2022 container on one EC2 host (no RDS).
# The DMS replication subnet group needs subnets in >= 2 AZs - hence the 2-AZ VPC.
#
# On-demand. `make destroy ENV=sqlmod` after the demo.

module "network" {
  source = "../../modules/network"

  name     = "fbctf-sqlmod"
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "random_password" "sa" {
  length           = 24
  override_special = "_-+=."
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "sa" {
  name                    = "fbctf-sqlmod/sa"
  description             = "SQL Server sa login (mssql container on EC2)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sa" {
  secret_id     = aws_secretsmanager_secret.sa.id
  secret_string = jsonencode({ username = "sa", password = random_password.sa.result })
}

resource "aws_security_group" "sqlserver" {
  name        = "fbctf-sqlmod-sqlserver"
  description = "SQL Server 1433 from within the VPC (the Transform DMS instance and the app tier)"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "TDS from the VPC"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fbctf-sqlmod-sqlserver" }
}

# ---- schema files staged in S3 (too large for user-data; fbctf-* is in scope)

resource "aws_s3_bucket" "schema" {
  bucket        = "fbctf-sqlmod-schema-337058058699-use1"
  force_destroy = true
  tags          = { Name = "fbctf-sqlmod-schema" }
}

resource "aws_s3_bucket_public_access_block" "schema" {
  bucket                  = aws_s3_bucket.schema.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "schema" {
  for_each = toset(["01_tables.sql", "02_programmability.sql", "03_seed.sql"])

  bucket = aws_s3_bucket.schema.id
  key    = each.value
  source = "${path.module}/../../modernization/sqlserver-schema/${each.value}"
  etag   = filemd5("${path.module}/../../modernization/sqlserver-schema/${each.value}")
}

resource "aws_s3_object" "app" {
  for_each = var.deploy_app ? toset(["Default.aspx", "web.config"]) : []

  bucket = aws_s3_bucket.schema.id
  key    = "app/${each.value}"
  source = "${path.module}/app/${each.value}"
  etag   = filemd5("${path.module}/app/${each.value}")
}

# ---- the SQL Server host: runs the container, then loads the schema and creates
# the read-only login Transform connects with.

resource "aws_iam_role" "host" {
  name = "fbctf-sqlmod-host"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "host_access" {
  name = "read-secret-and-schema"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.sa.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.schema.arn, "${aws_s3_bucket.schema.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "fbctf-sqlmod-host"
  role = aws_iam_role.host.name
}

resource "aws_instance" "sqlserver" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.sqlserver_instance_type
  subnet_id              = module.network.private_app_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.sqlserver.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  instance_initiated_shutdown_behavior = "stop"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 80
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/sqlserver-user-data.sh.tpl", {
    region        = var.region
    sa_secret_arn = aws_secretsmanager_secret.sa.arn
    ro_password   = var.transform_ro_password
    schema_bucket = aws_s3_bucket.schema.id
    mssql_image   = var.mssql_image
  })

  tags = { Name = "fbctf-sqlmod-sqlserver" }

  # The container's data lives on this instance; a user_data edit must not
  # recycle it. Re-run the loader over SSM if the schema logic changes.
  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [aws_secretsmanager_secret_version.sa, aws_s3_object.schema]
}

# ---- Contoso Scoreboard: the legacy .NET Framework app that consumes this
# SQL Server. Deployed live so the assessment sees a real Windows + IIS +
# .NET Framework + SQL Server workload and feature 10a has an app data layer
# to rewrite, not just a schema.

data "aws_ssm_parameter" "windows2022" {
  count = var.deploy_app ? 1 : 0
  name  = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

resource "random_password" "app" {
  count            = var.deploy_app ? 1 : 0
  length           = 24
  override_special = "_-+=."
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "app" {
  count                   = var.deploy_app ? 1 : 0
  name                    = "fbctf-sqlmod/scoreboard-app"
  description             = "scoreboard_app SQL login used by the Contoso Scoreboard web app"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  count         = var.deploy_app ? 1 : 0
  secret_id     = aws_secretsmanager_secret.app[0].id
  secret_string = jsonencode({ username = "scoreboard_app", password = random_password.app[0].result })
}

resource "random_password" "app_winrm" {
  count            = var.deploy_app ? 1 : 0
  length           = 20
  override_special = "_-+=."
}

resource "aws_secretsmanager_secret" "app_winrm" {
  count                   = var.deploy_app ? 1 : 0
  name                    = "fbctf-sqlmod/app-winrm"
  description             = "discovery local admin on the Contoso app host (WinRM, for the AWS Transform discovery tool)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_winrm" {
  count         = var.deploy_app ? 1 : 0
  secret_id     = aws_secretsmanager_secret.app_winrm[0].id
  secret_string = jsonencode({ username = "discovery", password = random_password.app_winrm[0].result })
}

resource "aws_security_group" "app" {
  count       = var.deploy_app ? 1 : 0
  name        = "fbctf-sqlmod-app"
  description = "Contoso Scoreboard: HTTP in, egress to SQL Server and AWS APIs"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.app_allow_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-sqlmod-app" }
}

resource "aws_iam_role" "app" {
  count = var.deploy_app ? 1 : 0
  name  = "fbctf-sqlmod-app"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  count      = var.deploy_app ? 1 : 0
  role       = aws_iam_role.app[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "app_access" {
  count = var.deploy_app ? 1 : 0
  name  = "read-secrets-and-app"
  role  = aws_iam_role.app[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [aws_secretsmanager_secret.sa.arn, aws_secretsmanager_secret.app[0].arn, aws_secretsmanager_secret.app_winrm[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.schema.arn, "${aws_s3_bucket.schema.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  count = var.deploy_app ? 1 : 0
  name  = "fbctf-sqlmod-app"
  role  = aws_iam_role.app[0].name
}

resource "aws_instance" "app" {
  count = var.deploy_app ? 1 : 0

  ami                    = data.aws_ssm_parameter.windows2022[0].value
  instance_type          = var.windows_instance_type
  subnet_id              = module.network.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.app[0].id]
  iam_instance_profile   = aws_iam_instance_profile.app[0].name

  instance_initiated_shutdown_behavior = "stop"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 60
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/windows-app-user-data.ps1.tpl", {
    region           = var.region
    sa_secret_arn    = aws_secretsmanager_secret.sa.arn
    app_secret_arn   = aws_secretsmanager_secret.app[0].arn
    winrm_secret_arn = aws_secretsmanager_secret.app_winrm[0].arn
    schema_bucket    = aws_s3_bucket.schema.id
    sql_host         = aws_instance.sqlserver.private_ip
    max_minutes      = 0
  })

  tags = { Name = "fbctf-sqlmod-app" }

  depends_on = [aws_s3_object.app, aws_secretsmanager_secret_version.app, aws_secretsmanager_secret_version.app_winrm, aws_instance.sqlserver]
}

resource "aws_eip" "app" {
  count    = var.deploy_app ? 1 : 0
  instance = aws_instance.app[0].id
  domain   = "vpc"
  tags     = { Name = "fbctf-sqlmod-app" }
}

# ---- Project Nami: a second app on this SQL Server - WordPress's SQL Server
# fork, on Ubuntu + Apache + PHP with the Microsoft pdo_sqlsrv driver. A
# legacy-PHP-on-a-commercial-DB workload for the assessment; its wordpress
# database is a second feature-10a target.

data "aws_ssm_parameter" "ubuntu2204" {
  count = var.deploy_wordpress ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "random_password" "wp" {
  count            = var.deploy_wordpress ? 1 : 0
  length           = 24
  override_special = "_-+=."
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "random_password" "wp_admin" {
  count            = var.deploy_wordpress ? 1 : 0
  length           = 20
  override_special = "_-+=."
}

resource "aws_secretsmanager_secret" "wp" {
  count                   = var.deploy_wordpress ? 1 : 0
  name                    = "fbctf-sqlmod/wordpress-db"
  description             = "wp_app SQL login used by Project Nami"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "wp" {
  count         = var.deploy_wordpress ? 1 : 0
  secret_id     = aws_secretsmanager_secret.wp[0].id
  secret_string = jsonencode({ username = "wp_app", password = random_password.wp[0].result, database = "wordpress" })
}

resource "aws_secretsmanager_secret" "wp_admin" {
  count                   = var.deploy_wordpress ? 1 : 0
  name                    = "fbctf-sqlmod/wordpress-admin"
  description             = "Project Nami wp-admin login"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "wp_admin" {
  count         = var.deploy_wordpress ? 1 : 0
  secret_id     = aws_secretsmanager_secret.wp_admin[0].id
  secret_string = jsonencode({ username = "admin", password = random_password.wp_admin[0].result })
}

resource "aws_security_group" "wordpress" {
  count       = var.deploy_wordpress ? 1 : 0
  name        = "fbctf-sqlmod-wordpress"
  description = "Project Nami: HTTP in, egress to SQL Server and package repos"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.wordpress_allow_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-sqlmod-wordpress" }
}

resource "aws_iam_role" "wordpress" {
  count = var.deploy_wordpress ? 1 : 0
  name  = "fbctf-sqlmod-wordpress"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "wordpress_ssm" {
  count      = var.deploy_wordpress ? 1 : 0
  role       = aws_iam_role.wordpress[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "wordpress_access" {
  count = var.deploy_wordpress ? 1 : 0
  name  = "read-secrets"
  role  = aws_iam_role.wordpress[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [aws_secretsmanager_secret.sa.arn, aws_secretsmanager_secret.wp[0].arn, aws_secretsmanager_secret.wp_admin[0].arn]
    }]
  })
}

resource "aws_iam_instance_profile" "wordpress" {
  count = var.deploy_wordpress ? 1 : 0
  name  = "fbctf-sqlmod-wordpress"
  role  = aws_iam_role.wordpress[0].name
}

resource "aws_instance" "wordpress" {
  count = var.deploy_wordpress ? 1 : 0

  ami                    = data.aws_ssm_parameter.ubuntu2204[0].value
  instance_type          = var.wordpress_instance_type
  subnet_id              = module.network.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.wordpress[0].id]
  iam_instance_profile   = aws_iam_instance_profile.wordpress[0].name

  instance_initiated_shutdown_behavior = "stop"
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 40
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/wordpress-user-data.sh.tpl", {
    region              = var.region
    sa_secret_arn       = aws_secretsmanager_secret.sa.arn
    wp_secret_arn       = aws_secretsmanager_secret.wp[0].arn
    wp_admin_secret_arn = aws_secretsmanager_secret.wp_admin[0].arn
    sql_host            = aws_instance.sqlserver.private_ip
    projectnami_zip_url = var.projectnami_zip_url
  })

  tags = { Name = "fbctf-sqlmod-wordpress" }

  depends_on = [aws_secretsmanager_secret_version.wp, aws_secretsmanager_secret_version.wp_admin, aws_instance.sqlserver]
}

resource "aws_eip" "wordpress" {
  count    = var.deploy_wordpress ? 1 : 0
  instance = aws_instance.wordpress[0].id
  domain   = "vpc"
  tags     = { Name = "fbctf-sqlmod-wordpress" }
}
