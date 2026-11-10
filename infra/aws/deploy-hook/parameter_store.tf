locals {
  parameter_path                 = "/${var.name_prefix}/deploy"
  queue_url_parameter_name       = "${local.parameter_path}/queue-url"
  approval_sender_parameter_name = "${local.parameter_path}/approval-sender-id"
}

resource "aws_ssm_parameter" "queue_url" {
  name  = local.queue_url_parameter_name
  type  = "String"
  tier  = "Standard"
  value = aws_sqs_queue.requests.url
}

resource "aws_ssm_parameter" "approval_sender_id" {
  name  = local.approval_sender_parameter_name
  type  = "String"
  tier  = "Standard"
  value = aws_iam_role.approval_forwarder.unique_id
}
