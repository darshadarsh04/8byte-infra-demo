output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "instance_id" {
  value       = aws_db_instance.this.id
  description = "The DBInstanceIdentifier CloudWatch alarms need for their dimensions"
}

output "allocated_storage_gb" {
  value       = aws_db_instance.this.allocated_storage
  description = "Single source of truth for the alerting module's storage alarm - avoids a second, easily-stale copy of this number in the environment config"
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  description = "Secrets Manager ARN holding the RDS-managed master password, consumed by the ECS task definition"
}
