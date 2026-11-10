locals {
  signing_name        = "${var.name_prefix}-image-signing"
  signing_key_actions = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign"]
}

resource "aws_kms_key" "image_signing" {
  description              = "cosign image signing key"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministers"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "image_signing" {
  name          = "alias/${local.signing_name}"
  target_key_id = aws_kms_key.image_signing.key_id
}

resource "aws_iam_role" "image_signing" {
  name = local.signing_name
  path = local.role_path
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.image_signing]
  })
}

resource "aws_iam_role_policy" "image_signing" {
  name = local.signing_name
  role = aws_iam_role.image_signing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SignImages"
        Effect   = "Allow"
        Action   = local.signing_key_actions
        Resource = [aws_kms_key.image_signing.arn]
      }
    ]
  })
}
