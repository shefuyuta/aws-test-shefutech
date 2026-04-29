terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "yutam-tf-state"
    key            = "env/dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-lock-table"
  }
}

provider "aws" {
  region = "us-west-2"
}