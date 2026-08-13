terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # NOTE: bootstrap intentionally uses LOCAL state — it creates the
  # remote-state backend that everything else will use.
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "state_bucket_name" {
  type    = string
  default = "expensy-tfstate-686699774218"
}

variable "lock_table_name" {
  type    = string
  default = "expensy-tf-locks"
}

# --- S3 bucket that stores terraform.tfstate ---
resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # safety: refuse accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

# versioning: keep history of state files (recover from bad applies)
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# encrypt state at rest (it can contain secrets)
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# block all public access to the state bucket
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DynamoDB table for state locking ---
resource "aws_dynamodb_table" "tf_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"   # no idle cost — only pay per lock op
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tf_state.id
}

output "lock_table" {
  value = aws_dynamodb_table.tf_locks.id
}
