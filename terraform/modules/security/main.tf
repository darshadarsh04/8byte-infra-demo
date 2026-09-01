###############################################################################
# Security groups for the 8bytes-demo three-tier stack + Windows bastion.
#
# Traffic chain (each hop is the ONLY way to reach the next):
#
#   internet ─▶ ALB ─▶ frontend ─▶ backend ─▶ rds
#                 └────────────────▶ backend        (ALB path-routes /api/* to backend)
#
#   office IP ─▶ bastion ─▶ frontend / backend / rds   (admin access only)
#
# Every rule below is a security-group-to-security-group reference where the
# source is another part of this stack; the only raw CIDR sources are the
# public internet (ALB :80/:443) and the office IP range (bastion :3389).
###############################################################################

# --- ALB: the only thing allowed to talk to the public internet ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Allow inbound HTTP/HTTPS from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

# --- Bastion: Windows admin jump host, reachable ONLY from the office IP ---
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Allow RDP from office IP only"
  vpc_id      = var.vpc_id

  ingress {
    description = "RDP from office network only"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.office_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-bastion-sg" }
}

# --- Frontend (nginx): reachable from the ALB, plus the bastion for admin ---
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-${var.environment}-frontend-sg"
  description = "Allow frontend port from ALB and bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Frontend port from ALB"
    from_port       = var.frontend_port
    to_port         = var.frontend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Frontend port from bastion (admin/debug)"
    from_port       = var.frontend_port
    to_port         = var.frontend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-frontend-sg" }
}

# --- Backend (API): reachable from the ALB (/api/*), the frontend, and the bastion ---
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend-sg"
  description = "Allow backend port from ALB, frontend, and bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend port from ALB (path-routed /api/*)"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Backend port from frontend (direct service-to-service)"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Backend port from bastion (admin/debug)"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-backend-sg" }
}

# --- RDS: reachable from the backend (app traffic) and the bastion (DB admin) ---
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Allow Postgres from backend and bastion only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description     = "Postgres from bastion (DB admin via psql/pgAdmin)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-rds-sg" }
}
