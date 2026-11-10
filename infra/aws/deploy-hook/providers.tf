provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = local.deploy_prefix
      managed-by = "terraform"
    }
  }
}
