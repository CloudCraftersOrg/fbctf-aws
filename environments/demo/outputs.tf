# Outputs are added per phase:
#   Phase 4: rds_endpoint, memcached_endpoint
#   Phase 6: alb_dns_name (the demo URL)

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.network.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  value = module.network.private_data_subnet_ids
}

output "nat_public_ip" {
  value = module.network.nat_public_ip
}

output "rds_endpoint" {
  value = module.database.endpoint
}

output "memcached_endpoint" {
  value = module.cache.endpoint
}

output "db_master_secret_arn" {
  value = module.database.master_user_secret_arn
}

output "db_app_secret_arn" {
  value = module.database.app_user_secret_arn
}

output "admin_secret_arn" {
  value = module.database.admin_secret_arn
}

output "nlb_dns" {
  value = module.nlb_internal.dns_name
}

output "app_asg_name" {
  value = module.service_tier_app.asg_name
}

output "web_asg_name" {
  value = module.service_tier_web.asg_name
}

# The demo URL.
output "alb_dns_name" {
  value = module.alb_external.dns_name
}
