variable "name" {
  description = "Name prefix (must start with fbctf-)"
  type        = string

  validation {
    condition     = startswith(var.name, "fbctf-")
    error_message = "The deploy permission set scopes named resources to fbctf-*; the name must start with fbctf-."
  }
}

variable "alb_arn_suffix" {
  type = string
}

variable "web_tg_arn_suffix" {
  type = string
}

variable "nlb_arn_suffix" {
  type = string
}

variable "app_tg_arn_suffix" {
  type = string
}

variable "db_identifier" {
  type = string
}
