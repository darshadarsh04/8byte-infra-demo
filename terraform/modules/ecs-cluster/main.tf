# One ECS cluster per environment, shared by every service (frontend, backend,
# and any future tier). Container Insights is on so per-task CPU/memory and the
# cluster-level metrics land in CloudWatch with no extra wiring.
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-${var.environment}" }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Each service picks its own capacity provider explicitly, so no default
  # strategy is set here - that keeps "staging uses Spot, prod uses on-demand"
  # a per-service decision instead of a cluster-wide one.
}
