variable "name" {
  type        = string
  description = "VPC NAME"
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "VPC cidr block"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Enter a valid cidr e.g 10.0.0.0/16"
  }
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to use"
  validation {
    condition     = length(var.azs) >= 2
    error_message = "Atleast 2 az are required for ALB and RDS"
  }
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "using a single nat-gateway for one az"
}
