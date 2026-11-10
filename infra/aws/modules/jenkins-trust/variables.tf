variable "provider_arn" {
  type        = string
  description = "ARN of the Jenkins OIDC provider."
}

variable "issuer" {
  type        = string
  description = "Jenkins OIDC issuer host and path, the prefix of the aud and sub condition keys."
}

variable "roles" {
  type = map(object({
    audience = string
    jobs     = list(string)
  }))
  description = "Token audience and Jenkins job names per role."
}
