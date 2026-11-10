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

variable "state_bucket" {
  type = string
  # change this: the S3 bucket that stores the Terraform state
  default = "your-tfstate-bucket"
}

variable "environments_path" {
  type        = string
  default     = "../../../environments"
  description = "Folder with one <service>.yaml per app, relative to this stack."
}

variable "github_owner_id" {
  type = string
  # change this: the numeric id of the GitHub org, used in the role trust of each app whose environments file sets repoId
  default     = "1234567"
  description = "GitHub ID of the owner of every app repo, for ID-form OIDC subjects."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub ID"
  }
}

variable "gitops_repo" {
  type = string
  # change this: the GitOps repo, as owner/name
  default     = "your-org/gitops"
  description = "Repo whose prod and dev pushes may send deploy requests."
}

variable "message_retention_seconds" {
  type        = number
  default     = 86400
  description = "Seconds a deploy request waits in the queue for the listener."
}

variable "max_receive_count" {
  type        = number
  default     = 5
  description = "Receives before a request moves to the dead-letter queue."
}

variable "terraform_job_name" {
  type        = string
  default     = "infra-aws"
  description = "Jenkins job that plans the AWS stacks and writes terraform requests."
}

variable "terraform_apply_job_name" {
  type        = string
  default     = "infra-aws-apply"
  description = "Jenkins job that applies an approved terraform request."
}

variable "alert_email" {
  type = string
  # change this: the address that receives the queue alarm emails
  default = "alerts@example.com"
}
