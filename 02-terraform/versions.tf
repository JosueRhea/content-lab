terraform {
  required_version = ">= 1.6"

  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 5.40, < 7.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Uncomment for the "state is shared infrastructure" segment.
  # Note use_lockfile: as of Terraform 1.10+ S3 does its own locking, so the old
  # DynamoDB lock table is no longer needed. Worth calling out live -- most
  # tutorials still tell people to create that table.
  #
  # backend "s3" {
  #   bucket       = "your-tf-state-bucket"
  #   key          = "content-lab/supabase/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "content-lab"
      Demo      = "supabase-iac"
      ManagedBy = "terraform"
    }
  }
}
