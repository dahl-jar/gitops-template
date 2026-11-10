locals {
  jenkins_image_jobs            = data.terraform_remote_state.account.outputs.jenkins_image_jobs
  jenkins_pull_jobs             = sort(concat(local.jenkins_image_jobs, [var.jenkins_scan_job_name]))
  jenkins_test_job_suffix       = "ci"
  jenkins_dev_job_suffix        = "dev"
  jenkins_production_job_suffix = "production"
  pages_target                  = "cloudflare-pages"
  jenkins_dependency_jobs = sort(flatten([
    for app in module.environments.apps : concat(
      ["${app.service}-${local.jenkins_test_job_suffix}", "${app.service}-${local.jenkins_dev_job_suffix}"],
      app.environments.production.target == local.pages_target ? ["${app.service}-${local.jenkins_production_job_suffix}"] : [],
    )
  ]))
  jenkins_trust = module.jenkins_trust.statements
}

module "jenkins_trust" {
  source       = "../modules/jenkins-trust"
  provider_arn = data.terraform_remote_state.account.outputs.jenkins_oidc_provider_arn
  issuer       = data.terraform_remote_state.account.outputs.jenkins_oidc_issuer
  roles = {
    push             = { audience = "aws-image-push", jobs = local.jenkins_image_jobs }
    pull             = { audience = "aws-image-pull", jobs = local.jenkins_pull_jobs }
    dependency_fetch = { audience = "aws-dependency-fetch", jobs = local.jenkins_dependency_jobs }
  }
}
