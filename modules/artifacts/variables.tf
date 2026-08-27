variable "bucket_name" {
  description = "Artifacts bucket name (must start with fbctf-; the deploy permission set scopes S3 to fbctf-*)"
  type        = string

  validation {
    condition     = startswith(var.bucket_name, "fbctf-")
    error_message = "Bucket name must start with fbctf-."
  }
}
