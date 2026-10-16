variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "vpc_cidr" {
  description = "alb egress allowing in vpc only"
  type        = string
}
variable "public_subnet_ids" {
  type = list(string)
}

variable "default_service" {
  type = string
}

variable "services" {
  type = map(object({
    port              = number
    health_check_path = string
    path_patterns     = list(string)
    priority          = optional(number)
    stickiness        = optional(bool, false)

  }))

  validation {
    condition     = contains(keys(var.services), var.default_service)
    error_message = "default_service must be one of the keys in services."
  }

}

variable "deletion_protection" {
  type    = bool
  default = false
}