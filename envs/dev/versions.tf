terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
  # Partial configuration: supply bucket/key/region/dynamodb_table with
  #   terraform init -backend-config=backend.hcl   (copy backend.hcl.example; created by ../../bootstrap)
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "examgadh"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "exam-gadh-terraform"
    }
  }
}
