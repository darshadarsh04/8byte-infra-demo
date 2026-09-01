#!/usr/bin/env bash
# Thin wrapper that fills in the partial S3 backend config (bucket + lock table,
# both of which embed the AWS account id) so you never edit backend.tf by hand.
#
#   ./scripts/tf.sh <staging|production> plan
#   ./scripts/tf.sh <staging|production> apply -var="frontend_image=..." -var="backend_image=..."
#
set -euo pipefail

PROJECT="${PROJECT_NAME:-8bytes-demo}"
ENVIRONMENT="${1:?usage: tf.sh <staging|production> <plan|apply|...> [args]}"
shift
CMD="${1:?usage: tf.sh <staging|production> <plan|apply|...> [args]}"
shift || true

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
LOCK="${PROJECT}-tfstate-lock"

cd "$(dirname "$0")/../terraform/environments/${ENVIRONMENT}"

terraform init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="dynamodb_table=${LOCK}"

if [ "$CMD" != "init" ]; then
  terraform "$CMD" "$@"
fi
