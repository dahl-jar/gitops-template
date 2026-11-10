module "environments" {
  source = "../modules/environments"

  environments_path = "${path.module}/${var.environments_path}"
  github_owner_id   = var.github_owner_id
}

locals {
  ecr_image_pattern = "^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/(.+)$"

  app_images = {
    for app in module.environments.apps : app.repo => distinct([
      for environment in values(app.environments) : regex(local.ecr_image_pattern, lookup(environment, "image", ""))[0]
      if can(regex(local.ecr_image_pattern, lookup(environment, "image", "")))
    ])
  }

  image_repositories = { for repo, names in local.app_images : repo => one(names) if length(names) > 0 }

  app_repositories = sort(distinct(values(local.image_repositories)))

  repositories = sort(distinct(concat(local.app_repositories, var.ci_push_repositories)))
}
