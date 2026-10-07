terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # bucket, dynamodb_table, and region are passed at init via -backend-config.
  backend "s3" {
    key = "30-iam.tfstate"
  }
}

provider "aws" {
  region = var.region
}
