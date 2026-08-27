variable "name" {
  description = "Tier name (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "instance_type" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "user_data" {
  description = "Rendered user-data script (plain text; module base64-encodes it)"
  type        = string
}

variable "target_group_arns" {
  type    = list(string)
  default = []
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "health_check_grace_period" {
  type    = number
  default = 900
}
