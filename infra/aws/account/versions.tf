terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71.0"
    }
  }

  backend "s3" {
    # change this: the S3 bucket that stores the Terraform state
    bucket = "your-tfstate-bucket"
    key    = "aws-account/terraform.tfstate"
    # change this: the AWS region of the state bucket
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
