variable "region" {
  description = "us-east-1 only — the deploy permission set's region lock and the Transform workspace both live there."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "region must be us-east-1 or us-west-2."
  }
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the estate VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "enable_windows_tier" {
  description = "Deploy the 6 Windows hosts (.NET Framework + SQL Server). Set false for a Linux-only, cheaper run."
  type        = bool
  default     = true
}

variable "enable_discovery_agent" {
  description = "Install the AWS Application Discovery Agent on every host. Off by default — the MPA CSV import in ../../inventory already covers discovery, and agent runs leave server records in Migration Hub after the fleet is destroyed."
  type        = bool
  default     = false
}

variable "max_lifetime_minutes" {
  description = "Every host runs `shutdown +N` at boot and terminates on shutdown, so the estate self-destructs even if `terraform destroy` is skipped."
  type        = number
  default     = 240

  validation {
    condition     = var.max_lifetime_minutes >= 30 && var.max_lifetime_minutes <= 720
    error_message = "max_lifetime_minutes must be 30-720."
  }
}
