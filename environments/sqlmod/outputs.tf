output "sql_server_address" {
  description = "Give this to the AWS Transform SQL Server modernization job"
  value       = aws_db_instance.sqlserver.address
}

output "sql_server_port" {
  value = aws_db_instance.sqlserver.port
}

output "database_name" {
  value = "Scoreboard"
}

output "master_user_secret_arn" {
  description = "RDS-managed master credentials (sqladmin)"
  value       = aws_db_instance.sqlserver.master_user_secret[0].secret_arn
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

output "rds_security_group_id" {
  description = "Add Transform's DMS instance to a group allowed inbound here, or it is already covered by the VPC CIDR rule"
  value       = aws_security_group.rds.id
}

output "loader_instance_id" {
  description = "SSM target — check /var/log/user-data.log for the schema-load result"
  value       = aws_instance.loader.id
}
