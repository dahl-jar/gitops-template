locals {
  approval_capacity_units = 1
  approval_key_attribute  = "request_id"
  approval_ttl_attribute  = "expires_at"
}

resource "aws_dynamodb_table" "approvals" {
  name                        = "${local.deploy_prefix}-approvals"
  billing_mode                = "PROVISIONED"
  read_capacity               = local.approval_capacity_units
  write_capacity              = local.approval_capacity_units
  hash_key                    = local.approval_key_attribute
  deletion_protection_enabled = true

  attribute {
    name = local.approval_key_attribute
    type = "S"
  }

  ttl {
    attribute_name = local.approval_ttl_attribute
    enabled        = true
  }
}

# change this: grant dynamodb:PutItem on this table to the role that records decisions
resource "aws_dynamodb_table" "decisions" {
  name                        = "${local.deploy_prefix}-decisions"
  billing_mode                = "PROVISIONED"
  read_capacity               = local.approval_capacity_units
  write_capacity              = local.approval_capacity_units
  hash_key                    = local.approval_key_attribute
  stream_enabled              = true
  stream_view_type            = "NEW_AND_OLD_IMAGES"
  deletion_protection_enabled = true

  attribute {
    name = local.approval_key_attribute
    type = "S"
  }

  ttl {
    attribute_name = local.approval_ttl_attribute
    enabled        = true
  }
}
