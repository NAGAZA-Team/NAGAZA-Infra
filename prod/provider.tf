terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    bucket         = "nagaza-tfstate"
    key            = "terraform/nagaza-prod/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "nagaza-terraform-lock"
  }
}

provider "aws" {
  region = "ap-northeast-2"
}
