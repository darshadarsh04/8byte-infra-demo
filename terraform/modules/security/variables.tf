variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "frontend_port" {
  type    = number
  default = 80
}

variable "backend_port" {
  type    = number
  default = 3000
}

variable "office_cidrs" {
  type        = list(string)
  description = "CIDR(s) allowed to RDP into the bastion, e.g. [\"203.0.113.10/32\"]. NEVER set this to 0.0.0.0/0."

  validation {
    condition     = !contains(var.office_cidrs, "0.0.0.0/0")
    error_message = "office_cidrs must not contain 0.0.0.0/0 - the bastion must be locked to the office network."
  }
}
