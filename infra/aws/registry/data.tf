data "aws_caller_identity" "current" {}

data "terraform_remote_state" "account" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "aws-account/terraform.tfstate"
    region = var.region
  }
}

locals {
  github_oidc_provider_arn = data.terraform_remote_state.account.outputs.github_oidc_provider_arn
  trust_anchor_arn         = data.terraform_remote_state.account.outputs.trust_anchor_arn
  role_path                = "/${var.name_prefix}/"
  github_oidc_host         = "token.actions.githubusercontent.com"
  github_oidc_audience     = "sts.amazonaws.com"

  github_trust = {
    Effect    = "Allow"
    Principal = { Federated = local.github_oidc_provider_arn }
    Action    = "sts:AssumeRoleWithWebIdentity"
  }
  github_audience_condition = { "${local.github_oidc_host}:aud" = local.github_oidc_audience }
}
