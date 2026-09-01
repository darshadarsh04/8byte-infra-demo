#!/usr/bin/env bash
# One-time setup. Creates the S3 state bucket, DynamoDB lock table, and the two
# ECR repositories. Safe to re-run (Terraform is idempotent). Run this BEFORE
# any environment apply.
#
#   ./scripts/bootstrap.sh
#
set -euo pipefail

PROJECT="${PROJECT_NAME:-8bytes-demo}"
REGION="${AWS_REGION:-us-east-1}"

cd "$(dirname "$0")/../terraform/bootstrap"

terraform init
terraform apply -var="project_name=${PROJECT}" -var="aws_region=${REGION}"

echo
echo "==== Bootstrap complete. Values you'll need: ===="
terraform output
