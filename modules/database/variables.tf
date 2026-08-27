variable "name" {
  description = "Name prefix (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "db_subnet_group_name" {
  description = "RDS subnet group (created by the network module)"
  type        = string
}

variable "rds_sg_id" {
  description = "Security group for the RDS instance"
  type        = string
}
