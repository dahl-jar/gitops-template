provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "${var.name_prefix}-account"
      managed-by = "terraform"
    }
  }
}
