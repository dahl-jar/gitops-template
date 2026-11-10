locals {
  pin_update_attributes = ["request_id", "status", "status_at", "status_detail"]
  update_return_values  = ["NONE"]
}

resource "aws_iam_role" "approval_request" {
  name = "${local.deploy_prefix}-request"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [module.jenkins_trust.statements.request]
  })
}

resource "aws_iam_role_policy" "approval_request" {
  name = "${local.deploy_prefix}-request"
  role = aws_iam_role.approval_request.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "PutRequests", Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.approvals.arn }
    ]
  })
}

resource "aws_iam_role" "approval_pin" {
  name = "${local.deploy_prefix}-pin"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [module.jenkins_trust.statements.pin]
  })
}

resource "aws_iam_role_policy" "approval_pin" {
  name = "${local.deploy_prefix}-pin"
  role = aws_iam_role.approval_pin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadRequests", Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.approvals.arn },
      { Sid = "ReadDecisions", Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.decisions.arn },
      {
        Sid      = "RecordRunOutcome"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.approvals.arn
        Condition = {
          "ForAllValues:StringEquals" = { "dynamodb:Attributes" = local.pin_update_attributes }
          StringEqualsIfExists        = { "dynamodb:ReturnValues" = local.update_return_values }
        }
      }
    ]
  })
}
