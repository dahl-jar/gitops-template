# change this: attach the policy that this role needs to run Terraform
resource "aws_iam_role" "terraform" {
  name = "${var.name_prefix}-terraform"
  path = local.role_path
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.jenkins_trust.terraform]
  })
}
