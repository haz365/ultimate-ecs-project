# ═══════════════════════════════════════════════════════════════
# DEV ENVIRONMENT BACKEND
# State stored in S3, locked with DynamoDB
# Key is unique per environment so states never overlap
# ═══════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-989346120260"
    key            = "ultimate-ecs/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ultimate-ecs"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "hustla"
    }
  }
}