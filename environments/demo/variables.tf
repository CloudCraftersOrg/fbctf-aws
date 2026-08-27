variable "region" {
  description = "AWS region for all resources. Must be us-east-1 or us-west-2 — the deploy permission set's region lockdown allows only those (us-east-1 chosen: colocated with the AWS Transform workspace)."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "owner" {
  description = "Owner tag applied to all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (subnet groups for RDS/ElastiCache require >= 2)"
  type        = number
  default     = 2
}
