terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap uses LOCAL state on purpose: it creates the S3 bucket + DynamoDB
  # lock table that every other stage uses as its s3 backend. No backend block.
}

provider "aws" {
  region = var.region
}
