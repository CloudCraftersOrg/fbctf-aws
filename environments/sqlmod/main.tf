# Live SQL Server for the one Transform capability that needs a real database:
# the full agentic SQL Server -> Aurora modernization job. Transform creates its
# own DMS replication instance inside this VPC, connects to the RDS instance,
# reads the schema, converts the stored procs and rewrites the .NET data layer.
#
# The DMS replication subnet group needs subnets in >= 2 AZs - that is why this
# has its own 2-AZ VPC rather than reusing anything single-AZ.
#
# On-demand only. `make destroy ENV=sqlmod` after the demo.

module "network" {
  source = "../../modules/network"

  name     = "fbctf-sqlmod"
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "rds" {
  name        = "fbctf-sqlmod-rds"
  description = "SQL Server 1433 from within the VPC (schema loader + the Transform DMS instance)"
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

  tags = { Name = "fbctf-sqlmod-rds" }
}

resource "aws_db_instance" "sqlserver" {
  identifier     = "fbctf-sqlmod"
  engine         = "sqlserver-ex"
  engine_version = var.sqlserver_engine_version
  instance_class = "db.t3.small"
  license_model  = "license-included"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = "sqladmin"
  manage_master_user_password = true

  db_subnet_group_name   = module.network.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = false
  publicly_accessible    = false

  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  backup_retention_period  = 0

  tags = { Name = "fbctf-sqlmod" }
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

# ---- schema loader: a throwaway host that runs the DDL, creates the read-only
# login Transform uses, then idles. `make destroy` removes it.

resource "aws_iam_role" "loader" {
  name = "fbctf-sqlmod-loader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "loader_ssm" {
  role       = aws_iam_role.loader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "loader_access" {
  name = "read-secret-and-schema"
  role = aws_iam_role.loader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_db_instance.sqlserver.master_user_secret[0].secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.schema.arn, "${aws_s3_bucket.schema.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "loader" {
  name = "fbctf-sqlmod-loader"
  role = aws_iam_role.loader.name
}

resource "aws_security_group" "loader" {
  name        = "fbctf-sqlmod-loader"
  description = "Schema loader: egress only (RDS, Secrets Manager, package repos, SSM)"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fbctf-sqlmod-loader" }
}

resource "aws_instance" "loader" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = module.network.private_app_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.loader.id]
  iam_instance_profile   = aws_iam_instance_profile.loader.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/load-schema.sh.tpl", {
    region        = var.region
    db_address    = aws_db_instance.sqlserver.address
    secret_arn    = aws_db_instance.sqlserver.master_user_secret[0].secret_arn
    ro_password   = var.transform_ro_password
    schema_bucket = aws_s3_bucket.schema.id
  })

  tags = { Name = "fbctf-sqlmod-loader" }

  depends_on = [aws_db_instance.sqlserver, aws_s3_object.schema]
}
