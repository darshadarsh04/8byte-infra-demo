variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "Email address to subscribe to the SNS alert topic. Leave empty to skip the email subscription."
}

variable "threshold_percent" {
  type        = number
  default     = 80
  description = "Utilization threshold (CPU, memory, storage) that triggers an alarm, as a percent."
}

# --- ECS ---
variable "ecs_cluster_name" {
  type = string
}

variable "ecs_services" {
  type        = list(string)
  description = "ECS service names to alarm on (e.g. [\"8bytes-demo-staging-frontend\", \"8bytes-demo-staging-backend\"])"
}

# --- RDS ---
variable "rds_instance_id" {
  type = string
}

variable "rds_allocated_storage_gb" {
  type        = number
  description = "Same value passed to the rds module's allocated_storage - used to convert the FreeStorageSpace alarm from bytes to a percent-remaining threshold."
}

variable "rds_max_connections" {
  type        = number
  default     = 100
  description = "Roughly db.t4g.micro/small's practical connection ceiling under this app's connection pool settings. Used as the 100% baseline for the DatabaseConnections alarm."
}

# --- ALB ---
variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffixes" {
  type        = map(string)
  description = "Map of tier name -> target group arn_suffix, e.g. { frontend = \"...\", backend = \"...\" }"
}
