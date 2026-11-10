locals {
  config_read_name      = "${var.name_prefix}-deploy-config-read"
  config_parameters_arn = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/${var.name_prefix}"

  config_paths = sort(distinct(flatten([
    for app in module.environments.apps : [
      for environment in app.environments : ["${app.service}/shared", "${app.service}/${environment.config}"]
      if lookup(environment, "config", "") != ""
    ]
  ])))

  config_parameter_arns = flatten([
    for path in local.config_paths : ["${local.config_parameters_arn}/${path}", "${local.config_parameters_arn}/${path}/*"]
  ])
}

resource "aws_iam_role" "config_read" {
  name = local.config_read_name
  path = local.role_path
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.config_read]
  })
}

resource "aws_iam_role_policy" "config_read" {
  name = local.config_read_name
  role = aws_iam_role.config_read.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAppConfig"
        Effect   = "Allow"
        Action   = ["ssm:GetParametersByPath", "ssm:GetParameter"]
        Resource = local.config_parameter_arns
      },
      {
        Sid      = "DecryptThroughSsm"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = local.kms_keys_arn
        Condition = {
          StringEquals = { "kms:ViaService" = local.ssm_service_host }
          StringLike   = { "kms:EncryptionContext:PARAMETER_ARN" = local.config_parameter_arns }
        }
      }
    ]
  })
}
