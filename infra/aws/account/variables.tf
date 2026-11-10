variable "region" {
  type = string
  # change this: the AWS region of every stack
  default = "eu-west-1"
}

variable "name_prefix" {
  type = string
  # change this: the prefix of every resource name, role path and parameter path
  default = "gitops"
}

variable "ca_certificate" {
  type = string
  # change this: the PEM certificate of the CA that signs the node and listener certificates
  default = <<-EOT
    -----BEGIN CERTIFICATE-----
    CHANGE_ME
    -----END CERTIFICATE-----
  EOT

  validation {
    condition     = startswith(var.ca_certificate, "-----BEGIN CERTIFICATE-----")
    error_message = "ca_certificate must be a PEM certificate that starts with -----BEGIN CERTIFICATE-----."
  }
}

variable "environments_path" {
  type        = string
  default     = "../../../environments"
  description = "Folder with one <service>.yaml per app, relative to the account stack."
}

variable "terraform_job_name" {
  type        = string
  default     = "infra-aws"
  description = "Jenkins job whose token may assume the terraform role."
}

variable "jenkins_jwks_file" {
  type        = string
  default     = "oidc/jwks.json"
  description = "JWKS file, relative to the account stack, with the public key that platform/jenkins/manifests/create-oidc-signing-key.sh writes."
}
