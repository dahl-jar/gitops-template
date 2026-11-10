locals {
  github_oidc_host     = "token.actions.githubusercontent.com"
  github_oidc_url      = "https://${local.github_oidc_host}"
  github_oidc_audience = "sts.amazonaws.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = local.github_oidc_url
  client_id_list = [local.github_oidc_audience]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_rolesanywhere_trust_anchor" "ca" {
  name    = "${var.name_prefix}-ca"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"

    source_data {
      x509_certificate_data = "${trimspace(var.ca_certificate)}\n"
    }
  }
}
