variable "function_name" {
  description = "<name_prefix>-image-processor"
  type        = string
}

variable "image_uri" {
  type = string
}

variable "bucket_id" {
  description = "S3 bucket (name) to trigger lambda"
  type        = string
}

variable "bucket_arn" {
  type = string
}

variable "trigger_prefix" {
  type    = string
  default = "uploads/"
}

variable "memory_size" {
  type    = number
  default = 1024
}

variable "timeout" {
  type    = number
  default = 60
}

variable "architecture" {
  type    = string
  default = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "secret_arns" {
  description = "Secrets Manager ARNs"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 14
}