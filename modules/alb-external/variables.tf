variable "name" {
  description = "ALB and target group name (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  type = string
}
