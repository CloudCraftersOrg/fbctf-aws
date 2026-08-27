# RDS MySQL 8.0 for the fbctf demo (§3.4, ADR 003).
#
# Auth-plugin note: HHVM 3.21's 2017-era client cannot speak
# caching_sha2_password (upstream MySQL 8's default). On RDS MySQL 8.0 the
# default_authentication_plugin parameter is IMMUTABLE — and already set to
# mysql_native_password (verified live 2026-08-27), so nothing to configure;
# the app user is additionally created IDENTIFIED WITH mysql_native_password
# explicitly during bootstrap. sql_mode is relaxed for 2018-era runtime
# queries (the schema import itself was validated clean under strict mode).

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-mysql80"
  family = "mysql8.0"

  parameter {
    name  = "sql_mode"
    value = "NO_ENGINE_SUBSTITUTION"
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.small"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "fbctf"
  username = "dbadmin"
  # Master password never touches Terraform state — RDS generates and stores
  # it in Secrets Manager (secret name rds!..., readable by the app role).
  manage_master_user_password = true

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.rds_sg_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az            = false
  publicly_accessible = false

  # Demo settings — this stack is destroyed after every session.
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  backup_retention_period  = 0
}

# Credentials for the application's own DB user. The app-tier user-data reads
# this secret and creates the user IDENTIFIED WITH mysql_native_password during
# the guarded DB bootstrap.
resource "random_password" "app_user" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_user" {
  name                    = "${var.name}/db-app-user"
  description             = "fbctf application DB user (created by app-tier bootstrap)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_user" {
  secret_id = aws_secretsmanager_secret.app_user.id
  secret_string = jsonencode({
    username = "ctf"
    password = random_password.app_user.result
    database = "fbctf"
  })
}

# Scoreboard admin login. Terraform owns the secret because the instance role
# can only READ fbctf-* secrets; the app-tier bootstrap hashes this password
# with the app's own extra/hash.php and inserts the admin team row.
resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  name                    = "${var.name}/admin-password"
  description             = "fbctf scoreboard admin login"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.admin.result
  })
}
