locals {
  listener_common_name         = "hook-listener"
  listener_credentials_seconds = 3600
}

resource "aws_iam_role" "listener" {
  name = "${local.deploy_prefix}-listener"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "HookListenerCertificate"
        Effect    = "Allow"
        Principal = { Service = "rolesanywhere.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
        Condition = {
          ArnEquals    = { "aws:SourceArn" = local.trust_anchor_arn }
          StringEquals = { "aws:PrincipalTag/x509Subject/CN" = local.listener_common_name }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "listener" {
  name = "${local.deploy_prefix}-listener"
  role = aws_iam_role.listener.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReceiveDeployRequests", Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage"], Resource = aws_sqs_queue.requests.arn },
      { Sid = "ReadQueueUrl", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = aws_ssm_parameter.queue_url.arn },
      { Sid = "ReadApprovalSender", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = aws_ssm_parameter.approval_sender_id.arn }
    ]
  })
}

resource "aws_rolesanywhere_profile" "listener" {
  name             = "${local.deploy_prefix}-listener"
  role_arns        = [aws_iam_role.listener.arn]
  duration_seconds = local.listener_credentials_seconds
  enabled          = true
}
