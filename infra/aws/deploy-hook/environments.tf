module "environments" {
  source = "../modules/environments"

  environments_path = "${path.module}/${var.environments_path}"
  github_owner_id   = var.github_owner_id
}

locals {
  github_repos = sort([for app in module.environments.apps : app.repo])
}
