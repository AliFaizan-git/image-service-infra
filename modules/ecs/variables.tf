variable "name" {
  type = string
}
variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "secret_arns" {
  type    = list(string)
  default = []
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "services" {
  description = "service key => container config"
  type = map(object({
    image            = string
    port             = number
    target_group_arn = string
    cpu              = optional(number, 256)
    memory           = optional(number, 512)
    desired_count    = optional(number, 1)
    environment      = optional(map(string), {})
    secrets          = optional(map(string), {}) # ENV_NAME => secret ARN (ya ARN:key::)
  }))
}

variable "task_role_policies" {
  type    = map(string)
  default = {}
}
