module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  single_nat_gateway   = true # staging: optimize for cost over AZ fault isolation
}

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  office_cidrs = var.office_cidrs
}

module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
}

module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id

  instance_class        = "db.t4g.micro" # smallest Graviton Postgres instance - fine for staging
  multi_az              = false
  backup_retention_days = 3
  deletion_protection   = false
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name = var.project_name
  environment  = var.environment
}

# --- Frontend tier (nginx static UI) ---
module "ecs_frontend" {
  source = "../../modules/ecs-service"

  project_name       = var.project_name
  environment        = var.environment
  service_name       = "frontend"
  cluster_id         = module.ecs_cluster.cluster_id
  cluster_name       = module.ecs_cluster.cluster_name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security.frontend_sg_id
  target_group_arn   = module.alb.frontend_target_group_arn
  container_image    = var.frontend_image
  container_port     = 80

  container_health_check_command = ["CMD-SHELL", "wget -q -O /dev/null http://localhost/healthz || exit 1"]

  desired_count    = 1
  min_capacity     = 1
  max_capacity     = 2
  use_fargate_spot = true # staging can tolerate a task being reclaimed

  depends_on = [module.ecs_cluster, module.alb]
}

# --- Backend tier (Express API) ---
module "ecs_backend" {
  source = "../../modules/ecs-service"

  project_name       = var.project_name
  environment        = var.environment
  service_name       = "backend"
  cluster_id         = module.ecs_cluster.cluster_id
  cluster_name       = module.ecs_cluster.cluster_name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security.backend_sg_id
  target_group_arn   = module.alb.backend_target_group_arn
  container_image    = var.backend_image
  container_port     = 3000

  environment_variables = [
    { name = "PORT", value = "3000" },
    { name = "DB_HOST", value = module.rds.address },
    { name = "DB_PORT", value = tostring(module.rds.port) },
    { name = "DB_NAME", value = module.rds.db_name },
  ]

  # DB_USER/DB_PASSWORD resolved from the RDS-managed secret at task launch -
  # never in the task def, never in state, never in `docker inspect`.
  secrets = [
    { name = "DB_USER", valueFrom = "${module.rds.master_user_secret_arn}:username::" },
    { name = "DB_PASSWORD", valueFrom = "${module.rds.master_user_secret_arn}:password::" },
  ]
  execution_secret_arns = [module.rds.master_user_secret_arn]

  container_health_check_command = ["CMD-SHELL", "node -e \"require('http').get('http://localhost:3000/health',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""]

  desired_count    = 1
  min_capacity     = 1
  max_capacity     = 2
  use_fargate_spot = true

  depends_on = [module.ecs_cluster, module.alb]
}

# --- Windows bastion (office-IP-only RDP + SSM) ---
module "bastion" {
  source = "../../modules/bastion"

  project_name     = var.project_name
  environment      = var.environment
  public_subnet_id = module.vpc.public_subnet_ids[0]
  bastion_sg_id    = module.security.bastion_sg_id
  create_key_pair  = true
}

# --- Alerting: SNS topic + threshold alarms across ECS, RDS, and ALB ---
module "alerting" {
  source = "../../modules/alerting"

  project_name = var.project_name
  environment  = var.environment
  alert_email  = var.alert_email

  ecs_cluster_name = module.ecs_cluster.cluster_name
  ecs_services     = [module.ecs_frontend.service_name, module.ecs_backend.service_name]

  rds_instance_id          = module.rds.instance_id
  rds_allocated_storage_gb = module.rds.allocated_storage_gb

  alb_arn_suffix = module.alb.alb_arn_suffix
  target_group_arn_suffixes = {
    frontend = module.alb.frontend_target_group_arn_suffix
    backend  = module.alb.backend_target_group_arn_suffix
  }
}
