locals {
  jenkins_oidc_bucket_name = "${var.name_prefix}-jenkins-oidc-${local.account_id}"
  jenkins_oidc_bucket_arn  = "arn:aws:s3:::${local.jenkins_oidc_bucket_name}"
  jenkins_oidc_path        = "jenkins"
  jenkins_discovery_key    = "${local.jenkins_oidc_path}/.well-known/openid-configuration"
  jenkins_jwks_key         = "${local.jenkins_oidc_path}/jwks"
  jenkins_oidc_object_arns = [for key in [local.jenkins_discovery_key, local.jenkins_jwks_key] : "${local.jenkins_oidc_bucket_arn}/${key}"]
  jenkins_jwks             = file("${path.module}/${var.jenkins_jwks_file}")
  jwk_public_members       = ["kty", "kid", "alg", "use", "n", "e"]
}

resource "aws_s3_bucket" "jenkins_oidc" {
  bucket = local.jenkins_oidc_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "jenkins_oidc" {
  bucket = aws_s3_bucket.jenkins_oidc.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "jenkins_oidc" {
  bucket                  = aws_s3_bucket.jenkins_oidc.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false

  depends_on = [aws_s3_bucket_ownership_controls.jenkins_oidc]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_oidc" {
  bucket = aws_s3_bucket.jenkins_oidc.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.jenkins_oidc]
}

resource "aws_s3_bucket_versioning" "jenkins_oidc" {
  bucket = aws_s3_bucket.jenkins_oidc.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.jenkins_oidc]
}

resource "aws_s3_bucket_policy" "jenkins_oidc" {
  bucket = aws_s3_bucket.jenkins_oidc.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicIssuerDocuments"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = local.jenkins_oidc_object_arns
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.jenkins_oidc_bucket_arn, "${local.jenkins_oidc_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_versioning.jenkins_oidc]
}

resource "aws_s3_object" "jenkins_oidc_discovery" {
  bucket       = aws_s3_bucket.jenkins_oidc.id
  key          = local.jenkins_discovery_key
  content      = templatefile("${path.module}/oidc/openid-configuration.json.tftpl", { issuer = local.jenkins_oidc_issuer_url })
  content_type = "application/json"

  depends_on = [aws_s3_bucket_policy.jenkins_oidc]
}

resource "aws_s3_object" "jenkins_oidc_jwks" {
  bucket       = aws_s3_bucket.jenkins_oidc.id
  key          = local.jenkins_jwks_key
  content      = local.jenkins_jwks
  content_type = "application/json"

  depends_on = [aws_s3_bucket_policy.jenkins_oidc]

  lifecycle {
    precondition {
      condition     = alltrue([for jwk in jsondecode(local.jenkins_jwks).keys : length(setsubtract(keys(jwk), local.jwk_public_members)) == 0])
      error_message = "The Jenkins JWKS file has a key member outside kty, kid, alg, use, n and e. Use only the public key."
    }

    precondition {
      condition     = sort([for jwk in jsondecode(local.jenkins_jwks).keys : jwk.kid]) == local.jenkins_credential_ids
      error_message = "The Jenkins JWKS file does not have exactly one entry for each credential id (${join(", ", local.jenkins_credential_ids)})."
    }

    precondition {
      condition     = length(distinct([for jwk in jsondecode(local.jenkins_jwks).keys : jwk.n])) == 1
      error_message = "The Jenkins JWKS entries have more than one modulus. Every credential id signs with one key."
    }
  }
}
