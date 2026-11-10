locals {
  push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:DescribeImages",
  ]

  app_repository_arns = [for name in local.app_repositories : local.repository_arns[name]]

  ci_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.ci_repo_name}@${var.ci_repo_id}:ref:refs/tags/*"
}

resource "aws_iam_role" "jenkins_push" {
  name = "${var.name_prefix}-jenkins-push"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.push]
  })
}

resource "aws_iam_role_policy" "jenkins_push" {
  name = "push"
  role = aws_iam_role.jenkins_push.name

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
        Sid      = "PushAppImages"
        Effect   = "Allow"
        Action   = local.push_actions
        Resource = local.app_repository_arns
      },
    ]
  })
}

resource "aws_iam_role" "ci_push" {
  name = "${var.name_prefix}-ci-push"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(local.github_trust, {
        Sid = "GithubPush"
        Condition = {
          StringEquals = local.github_audience_condition
          StringLike   = { "${local.github_oidc_host}:sub" = [local.ci_subject] }
        }
      }),
    ]
  })
}

resource "aws_iam_role_policy" "ci_push" {
  name = "push"
  role = aws_iam_role.ci_push.name

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
        Sid      = "PushCiImages"
        Effect   = "Allow"
        Action   = local.push_actions
        Resource = [for name in var.ci_push_repositories : local.repository_arns[name]]
      },
    ]
  })
}
