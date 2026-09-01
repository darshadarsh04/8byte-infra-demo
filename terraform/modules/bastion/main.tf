###############################################################################
# Windows bastion / jump host.
#
# Access model (two ways in, pick per your security posture):
#   1. RDP from the office IP only  - the bastion SG (in the security module)
#      allows TCP 3389 solely from var.office_cidrs. Uses the EC2 key pair below
#      to decrypt the Windows Administrator password.
#   2. SSM Fleet Manager / Session Manager - no inbound port at all. Enabled by
#      the AmazonSSMManagedInstanceCore policy on the instance role. This is the
#      more secure path; RDP is kept because the assignment asks for it.
#
# From here an admin can reach the frontend (:80), backend (:3000) and the
# database (:5432) - those three SGs each allow the bastion SG inbound.
###############################################################################

# Latest AWS-published Windows Server 2022 AMI - resolved at plan time so we're
# never pinned to a stale, unpatched image.
data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

#############################################
# Key pair
#############################################
# HOW THE KEY PAIR IS GENERATED (default path, create_key_pair = true):
#   - tls_private_key generates a 4096-bit RSA keypair inside Terraform.
#   - aws_key_pair uploads only the PUBLIC half to EC2.
#   - the PRIVATE half is stored in Secrets Manager (encrypted with KMS), NOT
#     printed to output and NOT left on anyone's laptop.
# Trade-off: the private key does land in Terraform state, which is why state
# lives in the encrypted, versioned, access-controlled S3 backend. If you'd
# rather the key never touch state at all, set create_key_pair = false and pass
# existing_key_name for a key you made out-of-band with:
#   aws ec2 create-key-pair --key-name 8bytes-demo-bastion \
#     --query KeyMaterial --output text > 8bytes-demo-bastion.pem
resource "tls_private_key" "bastion" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = "${var.project_name}-${var.environment}-bastion"
  public_key = tls_private_key.bastion[0].public_key_openssh

  tags = { Name = "${var.project_name}-${var.environment}-bastion" }
}

resource "aws_secretsmanager_secret" "bastion_key" {
  count                   = var.create_key_pair ? 1 : 0
  name                    = "${var.project_name}-${var.environment}-bastion-private-key"
  description             = "Private key (PEM) for the ${var.environment} Windows bastion. Used to decrypt the Administrator RDP password."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "bastion_key" {
  count         = var.create_key_pair ? 1 : 0
  secret_id     = aws_secretsmanager_secret.bastion_key[0].id
  secret_string = tls_private_key.bastion[0].private_key_pem
}

locals {
  key_name = var.create_key_pair ? aws_key_pair.bastion[0].key_name : var.existing_key_name
}

#############################################
# Instance role - enables SSM (no key/port needed for that path)
#############################################
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name
}

#############################################
# The bastion instance itself
#############################################
resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.bastion_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  key_name               = local.key_name

  # public IP so the office can reach it; SG still restricts to office CIDR only
  associate_public_ip_address = true

  # IMDSv2 required - blocks the SSRF-to-credential-theft class of attacks
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-bastion" }
}

# Stable public IP so the office firewall allow-list / DNS doesn't need updating
# every time the instance is replaced.
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = { Name = "${var.project_name}-${var.environment}-bastion-eip" }
}
