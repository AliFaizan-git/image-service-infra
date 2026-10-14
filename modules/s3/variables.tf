variable "bucket_name" {
  type = string

}
variable "force_destroy" {
  type    = bool
  default = true
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = []
}