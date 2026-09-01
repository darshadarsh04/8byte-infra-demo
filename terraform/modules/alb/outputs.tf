output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "frontend_target_group_arn_suffix" {
  value       = aws_lb_target_group.frontend.arn_suffix
  description = "Short-form ARN suffix CloudWatch alarms need for the TargetGroup dimension (the full ARN doesn't work here)"
}

output "backend_target_group_arn_suffix" {
  value       = aws_lb_target_group.backend.arn_suffix
  description = "Short-form ARN suffix CloudWatch alarms need for the TargetGroup dimension (the full ARN doesn't work here)"
}
