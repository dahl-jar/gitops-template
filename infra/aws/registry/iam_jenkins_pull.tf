resource "aws_iam_role" "jenkins_pull" {
  name = "${var.name_prefix}-jenkins-pull"
  path = local.role_path

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.pull]
  })
}

resource "aws_iam_role_policy" "jenkins_pull" {
  name   = "pull"
  role   = aws_iam_role.jenkins_pull.name
  policy = aws_iam_role_policy.node_pull.policy
}
