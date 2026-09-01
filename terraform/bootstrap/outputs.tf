output "state_bucket" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "Pass to `terraform init -backend-config=\"bucket=...\"` for each environment."
}

output "lock_table" {
  value       = aws_dynamodb_table.tf_lock.name
  description = "Pass to `terraform init -backend-config=\"dynamodb_table=...\"` for each environment."
}

output "frontend_ecr_repository_url" {
  value = aws_ecr_repository.this["frontend"].repository_url
}

output "backend_ecr_repository_url" {
  value = aws_ecr_repository.this["backend"].repository_url
}
