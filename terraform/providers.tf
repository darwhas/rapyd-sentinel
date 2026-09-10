terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "rapyd-sentinel"
      ManagedBy = "terraform"
      Owner     = "darwin-roso"
    }
  }
}

# Alias without default_tags: the challenge account denies
# iam:TagRole, so IAM roles must be created untagged.
provider "aws" {
  alias  = "no_default_tags"
  region = var.region
}