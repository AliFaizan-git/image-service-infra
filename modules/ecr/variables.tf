variable "repositories" {
  description = "ECR repo names"
  type        = string

}

variable "keep_last_images" {
  type    = number
  default = 3
}

variable "force_delete" {
  description = "destroying repo with images"
  type        = bool
  default     = true
}