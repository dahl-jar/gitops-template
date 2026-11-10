locals {
  github_oidc_host     = "token.actions.githubusercontent.com"
  github_oidc_audience = "sts.amazonaws.com"
  deploy_branches      = ["prod", "dev"]

  app_branch_refs = "refs/heads/*"

  app_push_subjects = [
    for repo in local.github_repos : "${module.environments.github_subjects[repo]}:ref:${local.app_branch_refs}"
  ]
  gitops_push_subjects = [
    for branch in local.deploy_branches : "repo:${var.gitops_repo}:ref:refs/heads/${branch}"
  ]

  send_statement = { Sid = "SendDeployRequests", Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.requests.arn }

  app_sender_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.send_statement]
  })

  gitops_sender_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.send_statement,
      { Sid = "ReadQueueUrl", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = aws_ssm_parameter.queue_url.arn }
    ]
  })
}

resource "aws_iam_role" "github_app" {
  name = "${local.deploy_prefix}-github-app"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AppRepoBranchPushes"
        Effect    = "Allow"
        Principal = { Federated = data.terraform_remote_state.account.outputs.github_oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.github_oidc_host}:aud" = local.github_oidc_audience
          }
          StringLike = {
            "${local.github_oidc_host}:sub" = local.app_push_subjects
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_app" {
  name   = "${local.deploy_prefix}-github-app"
  role   = aws_iam_role.github_app.id
  policy = local.app_sender_policy
}

resource "aws_iam_role" "github_gitops" {
  name = "${local.deploy_prefix}-github-gitops"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "GitopsDeployBranches"
        Effect    = "Allow"
        Principal = { Federated = data.terraform_remote_state.account.outputs.github_oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.github_oidc_host}:aud" = local.github_oidc_audience
            "${local.github_oidc_host}:sub" = local.gitops_push_subjects
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_gitops" {
  name   = "${local.deploy_prefix}-github-gitops"
  role   = aws_iam_role.github_gitops.id
  policy = local.gitops_sender_policy
}
