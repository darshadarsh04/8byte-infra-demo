# Challenges & resolutions

## RDS-managed master password vs. Terraform's usual "random_password + secret" pattern

My first pass at the RDS module used the pattern I've used before - a `random_password`
resource feeding into `aws_db_instance.password` directly, with a separate
`aws_secretsmanager_secret` to stash it for the app to read. Realized partway through that
this means the plaintext password sits in Terraform state twice (once as the resource
attribute, once mirrored into the secret), which is exactly the kind of thing I'd flag in
someone else's PR. Switched to `manage_master_user_password = true`, which is a newer RDS
feature that has RDS generate and own the secret directly - Terraform never sees the
plaintext at all. Small change, but it removed an entire category of "don't accidentally
commit or expose .tfstate" risk.

## Terraform lifecycle conflict between CI-driven deploys and `terraform apply`

The ECS service's `task_definition` argument and the CD pipeline's `aws ecs update-service
--force-new-deployment` step were fighting each other on the first pass - every
`terraform apply` was trying to reset the service back to whatever task definition
revision Terraform last knew about, undoing deploys that happened via the CLI in between
applies. Added `lifecycle { ignore_changes = [task_definition] }` to the ECS service
resource so Terraform manages everything about the service *except* which task definition
revision is currently running - that's deliberately left to the deploy pipeline. Worth
flagging as a real trade-off: it means `terraform plan` will never show you the "true"
current task definition revision without checking the AWS console/CLI directly, since
Terraform is intentionally blind to that one field.

## Couldn't fully validate the Terraform against real AWS

No AWS credentials in this environment, so everything here is validated by HCL syntax
parsing and careful manual review against the AWS provider docs, not an actual
`terraform plan`/`apply` against a live account. I'm confident in the shape of it, but
if I were reviewing this as someone else's PR, the thing I'd want before merging is a
`terraform plan` run against a real (even brand new, empty) AWS account, since there are
always a few provider-argument specifics - exact IAM policy shapes, whatever the current
gp3 vs gp2 default is - that are easy to get subtly wrong without that feedback loop. If
given a live AWS account, this would be the very first thing I'd do before calling any of
it final.

## ECS service vs. capacity providers / ALB listener creation ordering

The frontend and backend services reference the cluster and their target groups, but not the
cluster's capacity-provider association or the ALB listener rule - so Terraform didn't know to
create those first, and a first apply could race (service created before `FARGATE_SPOT` is
associated, or before the backend target group is attached to a listener). Added explicit
`depends_on = [module.ecs_cluster, module.alb]` on both service modules so the cluster
(including capacity providers) and the ALB (including the listener rule) are fully up before
either service is created.

## Windows bastion key pair — where does the private key live?

The honest tension here: generating the key pair in Terraform is convenient and self-contained,
but it puts the private key material in state. I went with generate-in-Terraform as the default
(RSA 4096 via the `tls` provider, private half stored KMS-encrypted in Secrets Manager, never
printed), and leaned on the fact that state already lives in an encrypted, versioned, locked S3
bucket. But I left `create_key_pair = false` + `existing_key_name` as a first-class option for
anyone who'd rather create the key with `aws ec2 create-key-pair` out-of-band so it never hits
state at all. Documented both paths in the README, plus the SSM-no-key alternative, rather than
pretending there's one obviously-correct answer.
