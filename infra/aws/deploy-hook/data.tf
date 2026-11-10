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
  deploy_prefix    = "${var.name_prefix}-deploy"
  role_path        = "/${var.name_prefix}/"
  trust_anchor_arn = data.terraform_remote_state.account.outputs.trust_anchor_arn
}
