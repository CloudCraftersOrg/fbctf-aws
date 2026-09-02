variable "region" {
  description = "us-east-1 - colocated with the AWS Transform workspace and the other envs"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "The deploy permission set allows only us-east-1 or us-west-2."
  }
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the oramod VPC (a 2-AZ VPC so Transform's DMS instance for the Oracle -> Aurora job fits)"
  type        = string
  default     = "10.50.0.0/16"
}

variable "oracle_instance_type" {
  description = "Oracle XE needs ~2 GB RAM"
  type        = string
  default     = "t3.medium"
}

variable "oracle_image" {
  description = "Oracle XE container (community image, no-auth pull)"
  type        = string
  default     = "gvenzl/oracle-xe:21-slim"
}

variable "deploy_app" {
  description = "Deploy the Contoso Catalog app (Spring Boot / Java 8) against Oracle"
  type        = bool
  default     = true
}

variable "app_allow_cidr" {
  description = "CIDR allowed to reach the Catalog app on :80"
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}
