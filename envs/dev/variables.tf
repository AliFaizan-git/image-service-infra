variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "project" {
  type    = string
  default = "image-service"
}
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "github_owner" {
  description = "Github username"
  type        = string

}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"

}

variable "single_nat_gateway" {
  type    = bool
  default = true

}
variable "allow_force_destroy" {
  type    = bool
  default = true
}