# fbctf demo environment — module composition only, no resources.
# Phases land here incrementally (see ../../fbctf-aws-requirements.md §8):
#   Phase 2: module "artifacts"    — S3 bucket + vendored packages / patched app tarball
#   Phase 3: module "security"     — SG chain; module "iam" — instance roles/profiles
#   Phase 4: module "database"     — RDS MySQL 8.0; module "cache" — ElastiCache memcached
#   Phase 5: module "nlb_internal" + module "service_tier" (app/HHVM)
#   Phase 6: module "alb_external" + module "service_tier" (web/nginx)
#   Phase 7: observability + alarms

module "network" {
  source = "../../modules/network"

  name     = "fbctf-${var.env}"
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count
}

# The artifacts bucket lives in its own root (environments/artifacts) so it
# survives destroy cycles of this stack — referenced here by name only.
locals {
  artifacts_bucket     = "fbctf-${var.env}-artifacts-337058058699-use1"
  artifacts_bucket_arn = "arn:aws:s3:::fbctf-${var.env}-artifacts-337058058699-use1"
}

module "security" {
  source = "../../modules/security"

  name             = "fbctf-${var.env}"
  vpc_id           = module.network.vpc_id
  app_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 10 + i)]
}

module "iam" {
  source = "../../modules/iam"

  name                 = "fbctf-${var.env}"
  artifacts_bucket_arn = local.artifacts_bucket_arn
}

module "database" {
  source = "../../modules/database"

  name                 = "fbctf-${var.env}"
  db_subnet_group_name = module.network.database_subnet_group_name
  rds_sg_id            = module.security.rds_sg_id
}

module "cache" {
  source = "../../modules/cache"

  name            = "fbctf-${var.env}"
  subnet_ids      = module.network.private_data_subnet_ids
  memcached_sg_id = module.security.memcached_sg_id
}

module "config" {
  source = "../../modules/config"

  parameters = {
    db_endpoint          = module.database.endpoint
    mc_endpoint          = module.cache.endpoint
    db_master_secret_arn = module.database.master_user_secret_arn
    db_app_secret_arn    = module.database.app_user_secret_arn
    admin_secret_arn     = module.database.admin_secret_arn
    artifacts_bucket     = local.artifacts_bucket
    nlb_dns              = module.nlb_internal.dns_name
  }
}

module "nlb_internal" {
  source = "../../modules/nlb-internal"

  name       = "fbctf-${var.env}-app"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_app_subnet_ids
}

module "service_tier_app" {
  source = "../../modules/service-tier"

  name                  = "fbctf-${var.env}-app"
  instance_type         = "t3.medium"
  instance_profile_name = module.iam.app_instance_profile_name
  security_group_id     = module.security.app_sg_id
  subnet_ids            = module.network.private_app_subnet_ids
  target_group_arns     = [module.nlb_internal.target_group_arn]

  user_data = templatefile("${path.module}/../../modules/service-tier/templates/app-userdata.sh.tpl", {
    region           = var.region
    artifacts_bucket = local.artifacts_bucket
    prebuilt_key     = "prebuilt/fbctf-prebuilt-4ec9b6b.tgz"
  })

  # The template reads /fbctf/* params and secrets at boot; make sure they
  # exist before the first instance launches.
  depends_on = [module.config, module.database]
}

module "alb_external" {
  source = "../../modules/alb-external"

  name              = "fbctf-${var.env}-web"
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.security.alb_sg_id
}

module "service_tier_web" {
  source = "../../modules/service-tier"

  name                  = "fbctf-${var.env}-web"
  instance_type         = "t3.small"
  instance_profile_name = module.iam.web_instance_profile_name
  security_group_id     = module.security.web_sg_id
  subnet_ids            = module.network.private_app_subnet_ids
  target_group_arns     = [module.alb_external.target_group_arn]

  user_data = templatefile("${path.module}/../../modules/service-tier/templates/web-userdata.sh.tpl", {
    region           = var.region
    artifacts_bucket = local.artifacts_bucket
    prebuilt_key     = "prebuilt/fbctf-prebuilt-4ec9b6b.tgz"
  })

  # Reads /fbctf/nlb_dns at boot and proxies to the app tier — both must exist.
  depends_on = [module.config, module.service_tier_app]
}

module "observability" {
  source = "../../modules/observability"

  name              = "fbctf-${var.env}"
  alb_arn_suffix    = module.alb_external.alb_arn_suffix
  web_tg_arn_suffix = module.alb_external.tg_arn_suffix
  nlb_arn_suffix    = module.nlb_internal.nlb_arn_suffix
  app_tg_arn_suffix = module.nlb_internal.tg_arn_suffix
  db_identifier     = module.database.identifier
}
