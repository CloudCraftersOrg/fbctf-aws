variable "region" {
  description = "Must be us-east-1 — AWS Transform SQL Server modernization is us-east-1 only."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "AWS Transform SQL Server modernization is only available in us-east-1."
  }
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the sqlmod VPC. Transform's DMS replication instance is created inside it."
  type        = string
  default     = "10.40.0.0/16"
}

variable "sqlserver_engine_version" {
  description = "RDS SQL Server Express engine version"
  type        = string
  default     = "15.00" # SQL Server 2019
}

variable "transform_ro_password" {
  description = "Password for the transform_ro SQL login (VIEW DEFINITION + VIEW DATABASE STATE). Printable ASCII only."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[[:print:]]{12,64}$", var.transform_ro_password)) && !can(regex("[[:space:]]", var.transform_ro_password))
    error_message = "transform_ro_password must be 12-64 printable ASCII characters with no whitespace."
  }
}
