# Partial backend config: the static bits live here, and the bucket + lock table
# (which contain the AWS account id) are supplied at init time via -backend-config.
# scripts/tf.sh computes and passes them; in CI the workflow does the same. This
# removes the old REPLACE_WITH_* placeholders so a fresh clone can't silently
# point at the wrong state.
terraform {
  backend "s3" {
    key     = "staging/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # bucket         = "<project>-tfstate-<account_id>"   (via -backend-config)
    # dynamodb_table = "<project>-tfstate-lock"           (via -backend-config)
  }
}
