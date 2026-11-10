locals {
  statements = {
    for role, access in var.roles : role => {
      Sid       = "JenkinsJobToken"
      Effect    = "Allow"
      Principal = { Federated = var.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.issuer}:aud" = access.audience
          "${var.issuer}:sub" = access.jobs
        }
      }
    }
  }
}
