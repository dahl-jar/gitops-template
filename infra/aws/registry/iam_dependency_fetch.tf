resource "aws_iam_role" "dependency_fetch" {
  name = "${local.resource_stem}-dependency-fetch"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.dependency_fetch]
  })
}

resource "aws_iam_role_policy" "dependency_fetch" {
  name   = "read"
  role   = aws_iam_role.dependency_fetch.name
  policy = local.dependency_read_policy
}
