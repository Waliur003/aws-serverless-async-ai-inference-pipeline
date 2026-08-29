//Declare terraform block with required providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}


//Declare provider block with region.
provider "aws" {
  region  = var.aws_region
}