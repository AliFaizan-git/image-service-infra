variable "aws-region" {
    description = "AWS region for remote bucket"
    type = string
    default = "eu-north-1"
  
}

variable "project" {
  description = "Project name"
  type = string
  default = "image-service"
}