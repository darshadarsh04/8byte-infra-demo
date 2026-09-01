project_name = "8bytes-demo"
environment  = "production"
aws_region   = "us-east-1"
azs          = ["us-east-1a", "us-east-1b"]
vpc_cidr     = "10.1.0.0/16"

# Darshan's office/home public IP - re-verify this hasn't changed before applying,
# since ISPs commonly rotate residential/office IPs over time.
office_cidrs = ["171.79.60.251/32"]

# Optional - set to receive CloudWatch alarm emails. Leave blank to skip.
alert_email = "darshadarsh04@gmail.com"
