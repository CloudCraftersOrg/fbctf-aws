variable "name" {
  description = "Name prefix for roles and instance profiles (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes IAM writes to fbctf-*; the name must start with fbctf-."
  }
}

variable "artifacts_bucket_arn" {
  description = "ARN of the artifacts bucket both tiers read from"
  type        = string
}
