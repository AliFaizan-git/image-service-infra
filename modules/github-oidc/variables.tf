variable "name_prefix" {
    type = string
  
}

variable "roles" {
  type = map(object({
    subjects = list(string)
    managed_policy_arns = optional(list(string))
    policy_json = optional(string)
  }))
}