# The third app in the demo stack: a Spring Boot 2.7 / Java 8 catalog service on
# an EC2, talking to Oracle Database 21c XE on another EC2. A textbook legacy
# enterprise workload for AWS Transform:
#   - Java 8 + Spring Boot 2 + javax.* + WebSecurityConfigurerAdapter -> Java 17
#   - Oracle schema (SEQUENCE + trigger, PL/SQL package, view) -> Aurora PostgreSQL
#   - the JPA / native-query data layer rewritten alongside the schema
#
# 2-AZ VPC so Transform's DMS replication instance for the Oracle job fits.
# On-demand. `make destroy ENV=oramod`.

module "network" {
  source = "../../modules/network"

  name     = "fbctf-oramod"
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "random_password" "sys" {
  length           = 24
  override_special = "_-."
}

resource "random_password" "catalog" {
  length           = 24
  override_special = "_-."
}

resource "random_password" "catalog_ro" {
  length           = 24
  override_special = "_-."
}

resource "random_password" "editor" {
  length           = 16
  override_special = "_-."
}

resource "aws_secretsmanager_secret" "sys" {
  name                    = "fbctf-oramod/oracle-sys"
  description             = "Oracle SYS / SYSTEM password (XE container on EC2)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sys" {
  secret_id     = aws_secretsmanager_secret.sys.id
  secret_string = jsonencode({ username = "system", password = random_password.sys.result })
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "fbctf-oramod/catalog-app"
  description             = "Contoso Catalog DB user + read-only Transform user + app editor login"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    username        = "catalog"
    password        = random_password.catalog.result
    ro_password     = random_password.catalog_ro.result
    editor_password = random_password.editor.result
    service         = "XEPDB1"
  })
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "fbctf-oramod-artifacts-337058058699-use1"
  force_destroy = true
  tags          = { Name = "fbctf-oramod-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "schema" {
  for_each = fileset("${path.module}/schema", "*.sql")

  bucket = aws_s3_bucket.artifacts.id
  key    = "schema/${each.value}"
  source = "${path.module}/schema/${each.value}"
  etag   = filemd5("${path.module}/schema/${each.value}")
}

data "archive_file" "app" {
  count       = var.deploy_app ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["target", ".gitignore"]
}

resource "aws_s3_object" "app" {
  count  = var.deploy_app ? 1 : 0
  bucket = aws_s3_bucket.artifacts.id
  key    = "app.zip"
  source = data.archive_file.app[0].output_path
  etag   = data.archive_file.app[0].output_md5
}

resource "aws_security_group" "oracle" {
  name        = "fbctf-oramod-oracle"
  description = "Oracle 1521 from within the VPC (the app tier and Transform DMS instance)"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "Oracle Net from the VPC"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fbctf-oramod-oracle" }
}

resource "aws_iam_role" "oracle" {
  name = "fbctf-oramod-oracle"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "oracle_ssm" {
  role       = aws_iam_role.oracle.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "oracle_access" {
  name = "read-secrets-and-schema"
  role = aws_iam_role.oracle.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [aws_secretsmanager_secret.sys.arn, aws_secretsmanager_secret.app.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "oracle" {
  name = "fbctf-oramod-oracle"
  role = aws_iam_role.oracle.name
}

resource "aws_instance" "oracle" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.oracle_instance_type
  subnet_id              = module.network.private_app_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.oracle.id]
  iam_instance_profile   = aws_iam_instance_profile.oracle.name

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

  user_data = templatefile("${path.module}/templates/oracle-user-data.sh.tpl", {
    region           = var.region
    sys_secret_arn   = aws_secretsmanager_secret.sys.arn
    app_secret_arn   = aws_secretsmanager_secret.app.arn
    artifacts_bucket = aws_s3_bucket.artifacts.id
    oracle_image     = var.oracle_image
  })

  tags = { Name = "fbctf-oramod-oracle" }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [aws_secretsmanager_secret_version.sys, aws_secretsmanager_secret_version.app, aws_s3_object.schema]
}

resource "aws_security_group" "app" {
  count       = var.deploy_app ? 1 : 0
  name        = "fbctf-oramod-app"
  description = "Contoso Catalog: HTTP in, egress to Oracle + build/package repos"
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
  tags = { Name = "fbctf-oramod-app" }
}

resource "aws_iam_role" "app" {
  count = var.deploy_app ? 1 : 0
  name  = "fbctf-oramod-app"
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
  name  = "read-secret-and-app"
  role  = aws_iam_role.app[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.app.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  count = var.deploy_app ? 1 : 0
  name  = "fbctf-oramod-app"
  role  = aws_iam_role.app[0].name
}

resource "aws_instance" "app" {
  count = var.deploy_app ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.app_instance_type
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
    volume_size = 30
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/app-user-data.sh.tpl", {
    region           = var.region
    app_secret_arn   = aws_secretsmanager_secret.app.arn
    artifacts_bucket = aws_s3_bucket.artifacts.id
    oracle_host      = aws_instance.oracle.private_ip
  })

  tags = { Name = "fbctf-oramod-app" }

  depends_on = [aws_s3_object.app, aws_instance.oracle]
}

resource "aws_eip" "app" {
  count    = var.deploy_app ? 1 : 0
  instance = aws_instance.app[0].id
  domain   = "vpc"
  tags     = { Name = "fbctf-oramod-app" }
}
