# Run this ONCE, manually, before anything else in this repo. It creates the
# shared, long-lived resources that must exist before (and survive) any
# environment:
#   - the S3 bucket + DynamoDB lock table that every environment's backend uses
#   - the ECR repositories for the frontend and backend images
#
# It deliberately uses LOCAL state (not the S3 backend) - you can't store the
# backend's own state in a backend that doesn't exist yet. ECR lives here rather
# than in an environment module so a `terraform destroy` on staging can never
# delete the image repositories.
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="project_name=8bytes-demo" -var="aws_region=us-east-1"

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "project_name" {
  type    = string
  default = "8bytes-demo"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

data "aws_caller_identity" "current" {}

#############################################
# Remote state backend
#############################################
resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

#############################################
# ECR repositories (one per tier)
#############################################
resource "aws_ecr_repository" "this" {
  for_each = toset(["frontend", "backend"])

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag (git sha) always means the same image

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep the last 20 images per repo; expire older untagged ones to control cost.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
