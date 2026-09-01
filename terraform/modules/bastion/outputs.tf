output "instance_id" {
  value = aws_instance.bastion.id
}

output "public_ip" {
  value       = aws_eip.bastion.public_ip
  description = "Elastic IP to RDP into (from the office network only)."
}

output "key_pair_name" {
  value = local.key_name
}

output "private_key_secret_arn" {
  value       = var.create_key_pair ? aws_secretsmanager_secret.bastion_key[0].arn : null
  description = "Secrets Manager ARN holding the bastion private key PEM (only when create_key_pair = true)."
}

output "get_password_hint" {
  value = <<-EOT
    To get the Windows Administrator password:
      1. aws secretsmanager get-secret-value --secret-id ${var.create_key_pair ? aws_secretsmanager_secret.bastion_key[0].name : "<your-secret>"} --query SecretString --output text > bastion.pem
      2. aws ec2 get-password-data --instance-id ${aws_instance.bastion.id} --priv-launch-key bastion.pem --query PasswordData --output text
    Then RDP to ${aws_eip.bastion.public_ip} as Administrator. (Or skip all of this and use SSM Fleet Manager - no key, no open port.)
  EOT
}
