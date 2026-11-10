locals {
  alarm_period_seconds         = 300
  alarm_evaluation_periods     = 1
  dead_letter_alarm_threshold  = 0
  oldest_request_alarm_seconds = 3600
}

resource "aws_sns_topic" "queue_alarms" {
  name = "${local.deploy_prefix}-queue-alarms"
}

resource "aws_sns_topic_subscription" "queue_alarms_email" {
  topic_arn = aws_sns_topic.queue_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dead_letter_messages" {
  alarm_name          = "${local.deploy_prefix}-dead-letter-messages"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.requests_dlq.name }
  statistic           = "Maximum"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.dead_letter_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.queue_alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "approval_failures" {
  alarm_name          = "${local.deploy_prefix}-approval-failures"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.approval_failures.name }
  statistic           = "Maximum"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.dead_letter_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.queue_alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "oldest_request_age" {
  alarm_name          = "${local.deploy_prefix}-oldest-request-age"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.requests.name }
  statistic           = "Maximum"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.oldest_request_alarm_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.queue_alarms.arn]
}
