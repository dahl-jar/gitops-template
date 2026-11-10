locals {
  long_poll_seconds             = 20
  visibility_timeout_seconds    = 120
  dead_letter_retention_seconds = 1209600
}

resource "aws_sqs_queue" "requests_dlq" {
  name                      = "${local.deploy_prefix}-requests-dlq"
  message_retention_seconds = local.dead_letter_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "requests" {
  name                       = "${local.deploy_prefix}-requests"
  receive_wait_time_seconds  = local.long_poll_seconds
  visibility_timeout_seconds = local.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.requests_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue" "approval_failures" {
  name                      = "${local.deploy_prefix}-approval-failures"
  message_retention_seconds = local.dead_letter_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "tls_only" {
  for_each = {
    requests          = aws_sqs_queue.requests
    requests_dlq      = aws_sqs_queue.requests_dlq
    approval_failures = aws_sqs_queue.approval_failures
  }

  queue_url = each.value.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyPlainHttp"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = each.value.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
