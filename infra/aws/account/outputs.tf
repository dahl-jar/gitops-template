output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "jenkins_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.jenkins.arn
}

output "jenkins_oidc_issuer" {
  value = local.jenkins_oidc_issuer
}

output "jenkins_image_jobs" {
  value = local.jenkins_image_jobs
}

output "trust_anchor_arn" {
  value = aws_rolesanywhere_trust_anchor.ca.arn
}

output "terraform_role_arn" {
  value = aws_iam_role.terraform.arn
}

output "config_read_role_arn" {
  value = aws_iam_role.config_read.arn
}

output "image_signing_role_arn" {
  value = aws_iam_role.image_signing.arn
}

output "image_signing_key_arn" {
  value = aws_kms_key.image_signing.arn
}
