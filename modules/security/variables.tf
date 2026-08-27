variable "name" {
  description = "Name prefix (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "vpc_id" {
  description = "VPC to create the security groups in"
  type        = string
}

variable "app_subnet_cidrs" {
  description = "Private app subnet CIDRs — the NLB nodes' ENIs live here; needed for TCP health checks to reach the app tier"
  type        = list(string)
}
