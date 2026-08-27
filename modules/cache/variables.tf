variable "name" {
  description = "Name prefix (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "subnet_ids" {
  description = "Private data subnet IDs for the cache subnet group"
  type        = list(string)
}

variable "memcached_sg_id" {
  description = "Security group for the memcached cluster"
  type        = string
}
