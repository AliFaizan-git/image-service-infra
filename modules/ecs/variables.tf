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
  type = map(object({
    image            = string
    port             = number
    target_group_arn = string
    cpu              = optional(number, 256)
    memory           = optiona(number, 512)
    desired_count    = optional(number, 1)
    secreccts        = optional(map(string), {})
    environments     = optional(map(string), {})

  }))
}

variable "task_role_policies" {
  type = map(string)
  default = {}
  }
