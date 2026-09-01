resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.project_name}-${var.environment}-db-subnets" }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-pg16"
  family = "postgres16"

  # log slow queries so they show up in the pg-log CloudWatch export -
  # this is what makes the "database metrics" dashboard requirement useful
  # rather than just CPU/connections
  parameter {
    name  = "log_min_duration_statement"
    value = "500" # ms
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-${var.environment}-db"
  engine         = "postgres"
  engine_version = "16.4"

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "appadmin"

  # Let RDS generate and own the master password in Secrets Manager rather
  # than us generating one in Terraform state - avoids the password ever
  # sitting in plaintext in a .tfstate file.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az            = var.multi_az
  publicly_accessible = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # free tier

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.project_name}-${var.environment}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}" : null

  tags = { Name = "${var.project_name}-${var.environment}-db" }

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
