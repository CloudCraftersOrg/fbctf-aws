output "sql_server_address" {
  description = "Give this to the AWS Transform SQL Server modernization job (private IP, reachable from within the VPC / the Transform DMS instance)"
  value       = aws_instance.sqlserver.private_ip
}

output "sql_server_port" {
  value = 1433
}

output "database_name" {
  value = "Scoreboard"
}

output "sa_secret_arn" {
  description = "Secrets Manager secret holding the sa login (fbctf-sqlmod/sa)"
  value       = aws_secretsmanager_secret.sa.arn
}

output "transform_login" {
  value = "transform_ro"
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "dms_subnet_ids" {
  description = "2-AZ subnets for Transform's DMS replication instance"
  value       = module.network.private_data_subnet_ids
}

output "sqlserver_security_group_id" {
  description = "1433 is open to the whole VPC CIDR; add Transform's DMS instance here only if you place it outside that range"
  value       = aws_security_group.sqlserver.id
}

output "sqlserver_instance_id" {
  description = "SSM target - /var/log/user-data.log has the container start + schema-load result"
  value       = aws_instance.sqlserver.id
}
