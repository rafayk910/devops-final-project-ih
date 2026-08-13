terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "expensy-tfstate-686699774218"
    key            = "expensy/main/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "expensy-tf-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
