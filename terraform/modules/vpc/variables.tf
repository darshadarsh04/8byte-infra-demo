variable "project_name" {
  type        = string
  description = "Short name used as a prefix on every resource, e.g. 8bytes-demo"
}

variable "environment" {
  type        = string
  description = "staging or production - kept as a plain string rather than an enum so a hotfix/preview env doesn't need a module change"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "At least 2 AZs for the ALB/RDS Multi-AZ requirement"
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "true = one NAT gateway shared by all private subnets (cheaper, single point of failure). Set false for production if the ~$32/mo per extra NAT gateway is worth the AZ-level fault isolation."
}
