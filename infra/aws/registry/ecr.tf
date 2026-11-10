locals {
  repository_arns = {
    for name in local.repositories : name => "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${name}"
  }

  lifecycle_policy = {
    rules = [
      {
        rulePriority = 1
        description  = "Keep release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.release_images_kept
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the newest main images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*.*.*-*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.main_images_kept
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
    ]
  }
}

resource "aws_ecr_repository" "image" {
  for_each = toset(local.repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = var.mutable_tag_filter
    filter_type = "WILDCARD"
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "image" {
  for_each = aws_ecr_repository.image

  repository = each.value.name
  policy     = jsonencode(local.lifecycle_policy)
}
