locals {
  pull_actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
}

resource "aws_iam_role" "node_pull" {
  name = "${var.name_prefix}-node-pull"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RolesAnywhereCertificate"
        Effect    = "Allow"
        Principal = { Service = "rolesanywhere.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
        Condition = {
          ArnEquals    = { "aws:SourceArn" = local.trust_anchor_arn }
          StringEquals = { "aws:PrincipalTag/x509Subject/CN" = var.node_pull_certificate_names }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "node_pull" {
  name = "pull"
  role = aws_iam_role.node_pull.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "PullImages"
        Effect   = "Allow"
        Action   = local.pull_actions
        Resource = values(local.repository_arns)
      },
    ]
  })
}

resource "aws_rolesanywhere_profile" "node_pull" {
  name             = "${var.name_prefix}-node-pull"
  role_arns        = [aws_iam_role.node_pull.arn]
  duration_seconds = var.credential_duration_seconds
  enabled          = true
}

resource "aws_iam_role" "verify" {
  name = "${var.name_prefix}-verify"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(local.github_trust, {
        Sid = "GithubVerify"
        Condition = {
          StringEquals = local.github_audience_condition
          StringLike   = { "${local.github_oidc_host}:sub" = ["repo:${var.gitops_repo}:*"] }
        }
      }),
    ]
  })
}

resource "aws_iam_role_policy" "verify" {
  name = "describe"
  role = aws_iam_role.verify.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeImages"
        Effect   = "Allow"
        Action   = "ecr:DescribeImages"
        Resource = values(local.repository_arns)
      },
    ]
  })
}
