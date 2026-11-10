locals {
  approval_forwarder_name      = "${local.deploy_prefix}-approval-forwarder"
  approval_forwarder_log_days  = 14
  approval_forwarder_memory_mb = 128
  approval_forwarder_timeout   = 10
  approval_stream_batch_size   = 1
  approval_stream_retries      = 2
  approval_stream_max_age      = 3600
  approved_decision_pattern    = jsonencode(jsondecode(file("${path.module}/lambda/approved_decision_filter.json")))
}

data "archive_file" "approval_forwarder" {
  type             = "zip"
  source_dir       = "${path.module}/lambda/approval_forwarder"
  output_path      = "${path.module}/.build/approval_forwarder.zip"
  output_file_mode = "0644"
  excludes         = ["__pycache__"]
}

resource "aws_cloudwatch_log_group" "approval_forwarder" {
  name              = "/aws/lambda/${local.approval_forwarder_name}"
  retention_in_days = local.approval_forwarder_log_days
}

resource "aws_iam_role" "approval_forwarder" {
  name = local.approval_forwarder_name
  path = local.role_path
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaService"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "approval_forwarder" {
  name = local.approval_forwarder_name
  role = aws_iam_role.approval_forwarder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDecisionStream"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
        Resource = aws_dynamodb_table.decisions.stream_arn
      },
      { Sid = "ListStreams", Effect = "Allow", Action = ["dynamodb:ListStreams"], Resource = "*" },
      { Sid = "ReadRequests", Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.approvals.arn },
      { Sid = "ReadDecisions", Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.decisions.arn },
      {
        Sid      = "SendApprovedRequests"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.requests.arn, aws_sqs_queue.approval_failures.arn]
      },
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.approval_forwarder.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "approval_forwarder" {
  function_name    = local.approval_forwarder_name
  role             = aws_iam_role.approval_forwarder.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.approval_forwarder.output_path
  source_code_hash = data.archive_file.approval_forwarder.output_base64sha256
  memory_size      = local.approval_forwarder_memory_mb
  timeout          = local.approval_forwarder_timeout

  environment {
    variables = {
      QUEUE_URL       = aws_sqs_queue.requests.url
      APPROVALS_TABLE = aws_dynamodb_table.approvals.name
      DECISIONS_TABLE = aws_dynamodb_table.decisions.name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.approval_forwarder.name
  }

  depends_on = [aws_iam_role_policy.approval_forwarder]
}

resource "aws_lambda_event_source_mapping" "approval_forwarder" {
  event_source_arn              = aws_dynamodb_table.decisions.stream_arn
  function_name                 = aws_lambda_function.approval_forwarder.arn
  starting_position             = "TRIM_HORIZON"
  batch_size                    = local.approval_stream_batch_size
  maximum_retry_attempts        = local.approval_stream_retries
  maximum_record_age_in_seconds = local.approval_stream_max_age

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.approval_failures.arn
    }
  }

  filter_criteria {
    filter {
      pattern = local.approved_decision_pattern
    }
  }

  depends_on = [aws_iam_role_policy.approval_forwarder]
}
