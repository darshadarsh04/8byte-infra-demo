variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet the bastion lives in (needs a route to the IGW for RDP from the office)."
}

variable "bastion_sg_id" {
  type        = string
  description = "The bastion security group (office-IP-only RDP), created in the security module."
}

variable "instance_type" {
  type    = string
  default = "t3.medium" # Windows needs a bit more headroom than Linux; t3.medium is a sane floor
}

variable "root_volume_size" {
  type    = number
  default = 50 # Windows base image is large
}

variable "create_key_pair" {
  type        = bool
  default     = true
  description = "true = Terraform generates the key pair and stores the private key in Secrets Manager. false = use existing_key_name for a key you created out-of-band."
}

variable "existing_key_name" {
  type        = string
  default     = ""
  description = "Name of a pre-existing EC2 key pair to use when create_key_pair = false."
}
