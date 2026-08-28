terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  backend "s3" {
    bucket  = "ekseks-project-backend"
    key     = "geon/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    #dynamodb_table = ""
  }
}


#리전
provider "aws" {
  region  = var.region
  profile = "geon"
}
