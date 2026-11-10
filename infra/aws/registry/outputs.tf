output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.image : name => repo.repository_url }
}

output "jenkins_push_role_arn" {
  value = aws_iam_role.jenkins_push.arn
}

output "jenkins_pull_role_arn" {
  value = aws_iam_role.jenkins_pull.arn
}

output "ci_push_role_arn" {
  value = aws_iam_role.ci_push.arn
}

output "node_pull_role_arn" {
  value = aws_iam_role.node_pull.arn
}

output "node_pull_profile_arn" {
  value = aws_rolesanywhere_profile.node_pull.arn
}

output "verify_role_arn" {
  value = aws_iam_role.verify.arn
}

output "trust_anchor_arn" {
  value = local.trust_anchor_arn
}

output "dependency_fetch_role_arn" {
  value = aws_iam_role.dependency_fetch.arn
}

output "dependency_domain" {
  value = aws_codeartifact_domain.dependencies.domain
}

output "dependency_domain_owner" {
  value = data.aws_caller_identity.current.account_id
}
