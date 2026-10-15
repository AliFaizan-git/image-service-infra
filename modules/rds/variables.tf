variable "name" {
  description = "base name"
  type        = string
}
variable "db_name" {
  type    = string
  default = "image-service"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "atlest 2 subnets are required for rds subnet group"
  }
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 10
}

variable "max_allocated_storage" {
  type    = number
  default = 20
}

variable "username" {
  type    = string
  default = "dbadmin"
}

variable "multi_az" {
  description = "false in dev want true only in prod"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}
variable "deletion_protection" {
  type    = bool
  default = false

}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
