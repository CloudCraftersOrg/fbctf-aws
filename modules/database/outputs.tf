output "endpoint" {
  value = aws_db_instance.this.address
}

output "master_user_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "app_user_secret_arn" {
  value = aws_secretsmanager_secret.app_user.arn
}

output "app_user_secret_name" {
  value = aws_secretsmanager_secret.app_user.name
}

output "admin_secret_arn" {
  value = aws_secretsmanager_secret.admin.arn
}

output "identifier" {
  value = aws_db_instance.this.identifier
}
