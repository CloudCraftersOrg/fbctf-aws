variable "name" {
  description = "Host name (must start with fbctf- for the deploy permission set)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "Named resources are scoped to fbctf-*; name must start with fbctf-."
  }
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "private_ip" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "instance_profile_name" {
  type = string
}

variable "user_data" {
  description = "Rendered user-data (shell for Linux, PowerShell wrapped in <powershell> for Windows)"
  type        = string
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
