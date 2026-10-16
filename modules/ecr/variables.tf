variable "repositories" {
  description = "ECR repo names"
  type        = list(string)

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

variable "image_tag_mutability" {
     type    = string
     default = "IMMUTABLE"

     validation {
       condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
       error_message = "Must be MUTABLE or IMMUTABLE."
     }
   }