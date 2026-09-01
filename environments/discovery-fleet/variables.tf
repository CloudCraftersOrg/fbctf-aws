variable "region" {
  description = "Must be us-east-1 — AWS Application Discovery Service's home region for this account, and an allowed region for the deploy permission set."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "Application Discovery Service data for this account lands in us-east-1; keep the fleet there."
  }
}

variable "owner" {
  description = "Owner tag applied to all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the throwaway discovery VPC"
  type        = string
  default     = "10.60.0.0/16"
}

variable "node_count" {
  description = "Number of collector nodes. 3-4 is enough to produce a dependency graph."
  type        = number
  default     = 4

  validation {
    condition     = var.node_count >= 2 && var.node_count <= 8
    error_message = "node_count must be between 2 and 8 — this is a demo, not a fleet."
  }
}

variable "instance_type" {
  description = "Graviton nano — the cheapest thing that runs the agent"
  type        = string
  default     = "t4g.nano"
}

variable "max_lifetime_minutes" {
  description = "Each node runs `shutdown -h +N` at boot and the launch template terminates on shutdown, so the fleet self-destructs even if `terraform destroy` is forgotten."
  type        = number
  default     = 180

  validation {
    condition     = var.max_lifetime_minutes >= 30 && var.max_lifetime_minutes <= 480
    error_message = "max_lifetime_minutes must be 30-480."
  }
}

variable "spot_max_price" {
  description = "Ceiling per hour. t4g.nano spot is ~$0.0013; empty string means the on-demand price is the cap."
  type        = string
  default     = ""
}
