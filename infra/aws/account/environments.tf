module "environments" {
  source = "../modules/environments"

  environments_path = "${path.module}/${var.environments_path}"
}

locals {
  jenkins_image_jobs = sort(flatten([
    for app in module.environments.apps : [
      for name, environment in app.environments : "${app.service}-${name}"
      if lookup(environment, "image", "") != ""
    ]
  ]))

  jenkins_config_jobs = sort(flatten([
    for app in module.environments.apps : [
      for name, environment in app.environments : "${app.service}-${name}"
      if lookup(environment, "config", "") != ""
    ]
  ]))
}
