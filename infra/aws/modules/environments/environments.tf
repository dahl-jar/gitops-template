locals {
  apps = [
    for name in fileset(var.environments_path, "*.yaml") :
    yamldecode(file("${var.environments_path}/${name}"))
  ]

  # change this: the GitHub OIDC subject of each app repo
  github_subjects = {
    for app in local.apps : app.repo => (
      lookup(app, "repoId", null) == null
      ? "repo:${app.repo}"
      : "repo:${split("/", app.repo)[0]}@${var.github_owner_id}/${split("/", app.repo)[1]}@${app.repoId}"
    )
  }
}
