locals {
  cluster_target = "cluster"

  jenkins_request_jobs = sort(concat(flatten([
    for app in module.environments.apps : [
      for name, environment in app.environments : "${app.service}-${name}"
      if lookup(environment, "target", "") == local.cluster_target
    ]
  ]), [var.terraform_job_name, var.terraform_apply_job_name]))

  jenkins_run_jobs = sort(concat([
    for app in module.environments.apps : "${app.service}-pin"
    if anytrue([for environment in values(app.environments) : lookup(environment, "target", "") == local.cluster_target])
  ], [var.terraform_apply_job_name]))
}

module "jenkins_trust" {
  source       = "../modules/jenkins-trust"
  provider_arn = data.terraform_remote_state.account.outputs.jenkins_oidc_provider_arn
  issuer       = data.terraform_remote_state.account.outputs.jenkins_oidc_issuer
  roles = {
    request = { audience = "aws-deploy-request", jobs = local.jenkins_request_jobs }
    pin     = { audience = "aws-deploy-pin", jobs = local.jenkins_run_jobs }
  }
}
