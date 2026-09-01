output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "Public URL of the app. Frontend at /, API at /api/*."
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "frontend_service_name" {
  value = module.ecs_frontend.service_name
}

output "backend_service_name" {
  value = module.ecs_backend.service_name
}

output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "bastion_get_password_hint" {
  value = module.bastion.get_password_hint
}
