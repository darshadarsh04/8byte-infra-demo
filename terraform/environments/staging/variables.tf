variable "project_name" {
  type    = string
  default = "8bytes-demo"
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "office_cidrs" {
  type        = list(string)
  description = "CIDR(s) allowed to RDP into the bastion. Set to your office public IP, e.g. [\"203.0.113.10/32\"]."
}

variable "frontend_image" {
  type        = string
  description = "Frontend image URI incl. tag. Set by CI at deploy time via -var."
}

variable "backend_image" {
  type        = string
  description = "Backend image URI incl. tag. Set by CI at deploy time via -var."
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "Email to receive CloudWatch alarm notifications. Leave empty to skip the subscription and only rely on the SNS topic (e.g. if you'll subscribe Slack separately)."
}
