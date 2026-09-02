variable "region" {
  description = "Must match where the sqlmod / oramod stacks run and the Transform assessment lives"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag"
  type        = string
}

variable "ui_allow_cidr" {
  description = "CIDR allowed to reach the discovery tool UI on :5000. Empty = SSM port-forward only (recommended)."
  type        = string
  default     = ""
}

variable "collector_instance_type" {
  description = "The discovery tool needs 4 vCPU / 16 GB"
  type        = string
  default     = "t3.xlarge"
}

variable "vpc_cidr" {
  description = "CIDR for the collector VPC (peered to the sqlmod and oramod VPCs)"
  type        = string
  default     = "10.70.0.0/16"
}

variable "max_lifetime_minutes" {
  description = "Hosts run `shutdown +N` at boot and terminate on shutdown. 0 disables auto-shutdown (hosts stay up until `make destroy`)."
  type        = number
  default     = 300

  validation {
    condition     = var.max_lifetime_minutes == 0 || (var.max_lifetime_minutes >= 60 && var.max_lifetime_minutes <= 1440)
    error_message = "max_lifetime_minutes must be 0 (disabled) or 60-1440."
  }
}

variable "discover_sqlmod" {
  description = "Also peer to the fbctf-sqlmod VPC and add its 3 hosts (SQL Server, Contoso .NET app, Project Nami) to the import list"
  type        = bool
  default     = true
}

variable "discover_oramod" {
  description = "Also peer to the fbctf-oramod VPC and add its 2 hosts (Oracle XE, Contoso Catalog / Java) to the import list"
  type        = bool
  default     = true
}

variable "enable_windows" {
  description = "Add a Windows Server + SQL Server Express host so the discovery tool exercises WinRM, the SQL Server module, and Windows OS discovery"
  type        = bool
  default     = true
}

variable "windows_instance_type" {
  type    = string
  default = "t3.small"
}
