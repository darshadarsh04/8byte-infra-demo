terraform {
  backend "s3" {
    key     = "production/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # bucket         = "<project>-tfstate-<account_id>"   (via -backend-config)
    # dynamodb_table = "<project>-tfstate-lock"           (via -backend-config)
  }
}
