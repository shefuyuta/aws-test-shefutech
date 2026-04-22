terraform {
  backend "s3" {
    bucket         = "yuta-tf-state-xxxx"   # 作成したS3
    key            = "env/dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-lock-table" # 作成したDynamoDB
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
