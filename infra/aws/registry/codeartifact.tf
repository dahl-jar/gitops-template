locals {
  resource_stem          = "${var.name_prefix}-${var.region}-${var.stage}"
  dependency_domain_name = "${local.resource_stem}-dependencies"
  dependency_stores = {
    "npm-store"            = "public:npmjs"
    "maven-store"          = "public:maven-central"
    "gradle-plugins-store" = "public:maven-gradleplugins"
  }
  dependency_consumers = {
    npm   = ["npm-store"]
    maven = ["maven-store", "gradle-plugins-store"]
  }
  codeartifact_arn_prefix  = "arn:aws:codeartifact:${var.region}:${data.aws_caller_identity.current.account_id}"
  dependency_domain_arn    = "${local.codeartifact_arn_prefix}:domain/${local.dependency_domain_name}"
  dependency_consumer_arns = [for name in sort(keys(local.dependency_consumers)) : "${local.codeartifact_arn_prefix}:repository/${local.dependency_domain_name}/${name}"]
  codeartifact_service     = "codeartifact.amazonaws.com"
  dependency_read_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "DependencyToken", Effect = "Allow", Action = ["codeartifact:GetAuthorizationToken"], Resource = [local.dependency_domain_arn] },
      { Sid = "DependencyRead", Effect = "Allow", Action = ["codeartifact:ReadFromRepository"], Resource = local.dependency_consumer_arns },
      {
        Sid       = "DependencyBearerToken"
        Effect    = "Allow"
        Action    = ["sts:GetServiceBearerToken"]
        Resource  = ["*"]
        Condition = { StringEquals = { "sts:AWSServiceName" = local.codeartifact_service } }
      },
    ]
  })
}

resource "aws_codeartifact_domain" "dependencies" {
  domain = local.dependency_domain_name
}

resource "aws_codeartifact_repository" "dependency_store" {
  for_each = local.dependency_stores

  repository  = each.key
  domain      = aws_codeartifact_domain.dependencies.domain
  description = "Packages fetched from ${each.value}"

  external_connections {
    external_connection_name = each.value
  }
}

resource "aws_codeartifact_repository" "dependency_consumer" {
  for_each = local.dependency_consumers

  repository  = each.key
  domain      = aws_codeartifact_domain.dependencies.domain
  description = "Read endpoint over ${join(", ", each.value)}"

  dynamic "upstream" {
    for_each = each.value
    content {
      repository_name = aws_codeartifact_repository.dependency_store[upstream.value].repository
    }
  }
}
