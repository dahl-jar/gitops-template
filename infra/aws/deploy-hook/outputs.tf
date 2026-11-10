output "deploy_hook_queue_url" {
  value = aws_sqs_queue.requests.url
}

output "deploy_hook_app_role_arn" {
  value = aws_iam_role.github_app.arn
}

output "deploy_hook_gitops_role_arn" {
  value = aws_iam_role.github_gitops.arn
}

output "deploy_hook_app_role_id" {
  value = aws_iam_role.github_app.unique_id
}

output "deploy_hook_gitops_role_id" {
  value = aws_iam_role.github_gitops.unique_id
}

output "listener_role_arn" {
  value = aws_iam_role.listener.arn
}

output "listener_profile_arn" {
  value = aws_rolesanywhere_profile.listener.arn
}

output "listener_trust_anchor_arn" {
  value = local.trust_anchor_arn
}

output "approvals_table_arn" {
  value = aws_dynamodb_table.approvals.arn
}

output "decisions_table_arn" {
  value = aws_dynamodb_table.decisions.arn
}

output "approval_request_role_arn" {
  value = aws_iam_role.approval_request.arn
}

output "approval_pin_role_arn" {
  value = aws_iam_role.approval_pin.arn
}

output "approval_forwarder_role_id" {
  value = aws_iam_role.approval_forwarder.unique_id
}

output "approval_failures_queue_url" {
  value = aws_sqs_queue.approval_failures.url
}
