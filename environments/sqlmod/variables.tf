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

variable "sqlserver_instance_type" {
  description = "SQL Server 2022 container needs ~4 GB RAM"
  type        = string
  default     = "t3.medium"
}

variable "mssql_image" {
  description = "SQL Server container image (Developer or Express edition set via MSSQL_PID in user-data)"
  type        = string
  default     = "mcr.microsoft.com/mssql/server:2022-latest"
}

variable "deploy_app" {
  description = "Deploy the Contoso Scoreboard app (Windows + IIS, ASP.NET Web Forms) against this SQL Server"
  type        = bool
  default     = true
}

variable "app_allow_cidr" {
  description = "CIDR allowed to reach the Contoso Scoreboard app on :80"
  type        = string
  default     = "0.0.0.0/0"
}

variable "windows_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "deploy_wordpress" {
  description = "Deploy Project Nami (WordPress fork for SQL Server) as a second app against this SQL Server"
  type        = bool
  default     = true
}

variable "wordpress_allow_cidr" {
  description = "CIDR allowed to reach the Project Nami site on :80"
  type        = string
  default     = "0.0.0.0/0"
}

variable "wordpress_instance_type" {
  type    = string
  default = "t3.small"
}

variable "projectnami_zip_url" {
  description = "Project Nami source archive (WordPress + the SQL Server db.php drop-in)"
  type        = string
  default     = "https://github.com/ProjectNami/projectnami/archive/refs/heads/master.zip"
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

variable "discovery_cidr" {
  description = "CIDR of the AWS Transform discovery collector VPC - opens SSH / WinRM inbound so its peered collector can reach these hosts. Empty disables."
  type        = string
  default     = "10.70.0.0/16"
}
