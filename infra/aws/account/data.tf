data "aws_caller_identity" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  role_path        = "/${var.name_prefix}/"
  ssm_service_host = "ssm.${var.region}.amazonaws.com"
  kms_keys_arn     = "arn:aws:kms:${var.region}:${local.account_id}:key/*"
}
