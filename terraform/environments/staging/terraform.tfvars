# Non-secret defaults for staging. The two image URIs are intentionally absent -
# CI always passes them explicitly with -var so a stale tag here can never be
# deployed by accident.
project_name = "8bytes-demo"
environment  = "staging"
aws_region   = "us-east-1"
azs          = ["us-east-1a", "us-east-1b"]
vpc_cidr     = "10.0.0.0/16"

# Darshan's office/home public IP - re-verify this hasn't changed before applying,
# since ISPs commonly rotate residential/office IPs over time.
office_cidrs = ["171.79.60.251/32"]

# Optional - set to receive CloudWatch alarm emails. Leave blank to skip.
alert_email = "darshadarsh04@gmail.com"
