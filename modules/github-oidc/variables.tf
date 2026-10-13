variable "name_prefix" {
  type = string

}

variable "thumbprint_list" {
  description = "A list of server certificate thumbprints for the OpenID Connect (OIDC) identity provider's server certificate(s)."
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "max_session_duration" {
  default     = 3600
  description = "Maximum session duration in seconds."
  type        = number
}
variable "github_owner" {
    description = "Github username"
    type = string
  
}

variable "roles" {
  type = map(object({
    subjects            = list(string)
    managed_policy_arns = optional(list(string))
    policy_json         = optional(string)
  }))
}
