variable "region" {
  description = "Must match where the fbctf demo runs and the Transform assessment lives"
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
  description = "CIDR for the collector VPC (peered to the fbctf demo VPC)"
  type        = string
  default     = "10.70.0.0/16"
}

variable "max_lifetime_minutes" {
  description = "Every host runs `shutdown +N` at boot and terminates on shutdown"
  type        = number
  default     = 300

  validation {
    condition     = var.max_lifetime_minutes >= 60 && var.max_lifetime_minutes <= 1440
    error_message = "max_lifetime_minutes must be 60-1440 (discovery needs time to sample metrics)."
  }
}

variable "discover_fbctf" {
  description = "Also peer to the fbctf demo VPC and add it to the import list (2 live app servers)"
  type        = bool
  default     = true
}
