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

variable "stage" {
  type    = string
  default = "prod"
}

variable "state_bucket" {
  type = string
  # change this: the S3 bucket that stores the Terraform state
  default = "your-tfstate-bucket"
}

variable "environments_path" {
  type    = string
  default = "../../../environments"
}

variable "mutable_tag_filter" {
  type    = string
  default = "sha256-*"
}

variable "ci_push_repositories" {
  type    = list(string)
  default = ["ci-tools", "hook-listener"]
}

variable "github_owner" {
  type = string
  # change this: the GitHub org
  default = "your-org"
}

variable "github_owner_id" {
  type = string
  # change this: the numeric id of the GitHub org, which the role trust checks to refuse a repo under a reused org or repo name
  default = "1234567"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub ID"
  }
}

variable "ci_repo_name" {
  type = string
  # change this: the repo that builds the CI images
  default = "ci-library"
}

variable "ci_repo_id" {
  type = string
  # change this: the numeric id of that repo
  default = "7654321"

  validation {
    condition     = can(regex("^[0-9]+$", var.ci_repo_id))
    error_message = "ci_repo_id must be a numeric GitHub ID"
  }
}

variable "gitops_repo" {
  type = string
  # change this: the GitOps repo, as owner/name
  default = "your-org/gitops"
}

variable "node_pull_certificate_names" {
  type = list(string)
  # change this: the certificate names of the nodes that pull images
  default = ["node1"]
}

variable "credential_duration_seconds" {
  type    = number
  default = 3600
}

variable "jenkins_scan_job_name" {
  type        = string
  default     = "scan-production-images"
  description = "Jenkins job that pulls the production images to scan them."
}

variable "release_images_kept" {
  type    = number
  default = 1000
}

variable "main_images_kept" {
  type    = number
  default = 30
}

variable "untagged_expiry_days" {
  type    = number
  default = 1
}
