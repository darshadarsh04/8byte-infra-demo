variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "service_name" {
  type        = string
  description = "Tier name, e.g. \"frontend\" or \"backend\". Used in resource names and the container name."
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "container_image" {
  type        = string
  description = "Full image URI incl. tag, passed in per-deploy from CI (not hardcoded)."
}

variable "container_port" {
  type = number
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 2
}

variable "use_fargate_spot" {
  type    = bool
  default = false
}

variable "environment_variables" {
  type        = list(object({ name = string, value = string }))
  default     = []
  description = "Plain (non-secret) env vars injected into the container."
}

variable "secrets" {
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
  description = "Secret env vars (valueFrom = Secrets Manager ARN, optionally with :key:: suffix), resolved at task launch."
}

variable "execution_secret_arns" {
  type        = list(string)
  default     = []
  description = "Secret ARNs the execution role is allowed to read. Usually the base ARNs of whatever is referenced in `secrets`."
}

variable "container_health_check_command" {
  type        = list(string)
  default     = null
  description = "Container-level health check command (ECS format). null = no container health check (ALB target group still health-checks)."
}

variable "log_retention_days" {
  type    = number
  default = 30
}
