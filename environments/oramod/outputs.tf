output "oracle_address" {
  description = "Give this to the AWS Transform Oracle -> Aurora job (private IP, reachable from within the VPC / the DMS instance)"
  value       = "${aws_instance.oracle.private_ip}:1521/XEPDB1"
}

output "oracle_instance_id" {
  description = "SSM target - /var/log/user-data.log has the container + schema-load result"
  value       = aws_instance.oracle.id
}

output "sys_secret_arn" {
  value = aws_secretsmanager_secret.sys.arn
}

output "app_secret_arn" {
  description = "catalog DB user, transform_ro password, and the app editor login"
  value       = aws_secretsmanager_secret.app.arn
}

output "transform_ro_user" {
  value = "transform_ro"
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "dms_subnet_ids" {
  description = "2-AZ subnets for Transform's DMS replication instance"
  value       = module.network.private_data_subnet_ids
}

output "app_url" {
  description = "Contoso Catalog (Spring Boot 2.7 / Java 8 on Oracle)"
  value       = var.deploy_app ? "http://${aws_eip.app[0].public_ip}/" : null
}

output "app_instance_id" {
  value = var.deploy_app ? aws_instance.app[0].id : null
}
