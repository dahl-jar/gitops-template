provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "${var.name_prefix}-registry"
      managed-by = "terraform"
    }
  }
}
