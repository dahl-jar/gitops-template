locals {
  jenkins_oidc_issuer           = "${local.jenkins_oidc_bucket_name}.s3.${var.region}.amazonaws.com/${local.jenkins_oidc_path}"
  jenkins_oidc_issuer_url       = "https://${local.jenkins_oidc_issuer}"
  jenkins_registry_audiences    = ["aws-image-push", "aws-image-pull", "aws-dependency-fetch"]
  jenkins_deploy_hook_audiences = ["aws-deploy-request", "aws-deploy-pin"]
  jenkins_roles = {
    terraform     = { audience = "aws-infra", jobs = [var.terraform_job_name] }
    config_read   = { audience = "aws-config-read", jobs = local.jenkins_config_jobs }
    image_signing = { audience = "aws-image-signing", jobs = local.jenkins_image_jobs }
  }
  jenkins_credential_ids = sort(concat([for access in values(local.jenkins_roles) : access.audience], local.jenkins_registry_audiences, local.jenkins_deploy_hook_audiences))
  jenkins_token_statement = {
    Sid       = "JenkinsJobToken"
    Effect    = "Allow"
    Principal = { Federated = aws_iam_openid_connect_provider.jenkins.arn }
    Action    = "sts:AssumeRoleWithWebIdentity"
  }
  jenkins_trust = {
    for role, access in local.jenkins_roles : role => merge(local.jenkins_token_statement, {
      Condition = {
        StringEquals = {
          "${local.jenkins_oidc_issuer}:aud" = access.audience
          "${local.jenkins_oidc_issuer}:sub" = access.jobs
        }
      }
    })
  }
}

resource "aws_iam_openid_connect_provider" "jenkins" {
  url            = local.jenkins_oidc_issuer_url
  client_id_list = toset(local.jenkins_credential_ids)

  depends_on = [aws_s3_bucket_policy.jenkins_oidc, aws_s3_object.jenkins_oidc_discovery, aws_s3_object.jenkins_oidc_jwks]

  lifecycle {
    prevent_destroy = true
  }
}
