terraform {
  backend "s3" {
    bucket         = "capstone-phoenix"
    key            = "capstone-phoenix/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "capstone-phoenix-terraform-lock"
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
