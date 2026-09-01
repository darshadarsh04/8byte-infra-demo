# Taskboard - three-tier app on AWS (frontend + backend + db)

A small task-list application (Taskboard) deployed on AWS with Terraform and shipped
through GitHub Actions. The app itself is intentionally simple - a few REST endpoints
over Postgres - since the point of this repo is the platform around it, not the app:

- **frontend** — static UI (nginx) on ECS Fargate
- **backend** — Express/Postgres REST API on ECS Fargate
- **db** — RDS Postgres in private subnets
- plus a **Windows bastion** for admin access to all three, locked to the office IP

Everything runs in `us-east-1`, and every resource is prefixed `8bytes-demo`.

```
internet ─▶ ALB ─┬─(/)      ▶ frontend (ECS) ─▶ backend (ECS) ─▶ RDS Postgres
                 └─(/api/*)  ▶ backend  (ECS) ─────────────────▶ RDS Postgres

office IP ─▶ Windows bastion ─▶ frontend / backend / RDS   (admin only)
```

One ALB, path-routed: `/` serves the frontend, `/api/*` goes to the backend. The
browser calls the API same-origin (`/api/...`), so there's no CORS and the backend
address never leaves the VPC.

## Terminology

Quick reference for the AWS terms used throughout this doc, for anyone reading this
who isn't AWS-fluent yet:

| Term | What it means here |
|------|---------------------|
| **VPC** (Virtual Private Cloud) | An isolated network in AWS that everything else in this repo lives inside |
| **Subnet** (public / private) | A slice of the VPC's IP range. Public subnets can route to the internet; private ones can't be reached from it directly |
| **NAT Gateway** | Lets things in a private subnet reach the internet (e.g. to pull a Docker image) without being reachable from it |
| **ALB** (Application Load Balancer) | The single internet-facing entry point; routes incoming requests to the frontend or backend |
| **Security Group (SG)** | A stateful firewall attached to a resource - "what's allowed to talk to this" |
| **ECS** (Elastic Container Service) | AWS's container orchestrator; runs the frontend and backend as containers |
| **Fargate** | The "serverless" way to run ECS containers - no EC2 instances to patch or manage |
| **RDS** (Relational Database Service) | Managed Postgres - AWS handles patching, backups, and failover |
| **IAM** (Identity and Access Management) | Controls who/what can do what in the AWS account - every role in this repo is an IAM role |
| **Execution role vs. task role** | Execution role = what ECS itself needs to start a container (pull image, write logs). Task role = what the running application code is allowed to do |
| **Secrets Manager** | Where the database password lives - encrypted, never in this repo or in plain Terraform state |
| **OIDC** (OpenID Connect) | How GitHub Actions authenticates to AWS without a stored, long-lived access key |
| **IMDSv2** | A hardened version of the EC2 metadata service that closes off a known SSRF-to-credential-theft attack path |
| **SSM** (Systems Manager) / Session Manager | Lets you reach the bastion instance without opening an RDP port or managing an SSH/RDP key at all |
| **ACM** (AWS Certificate Manager) | Where a TLS certificate would come from if HTTPS were added to the ALB (not yet implemented - see Security considerations) |

## Repo layout

```
frontend/                 nginx + static HTML/JS (the UI tier)
backend/                  Express + Postgres API (the API tier)
terraform/
  bootstrap/              one-time: S3 state bucket + DynamoDB lock + ECR repos
  modules/
    vpc/                  VPC, public/private subnets, NAT, flow logs
    security/             security groups: ALB / frontend / backend / rds / bastion
    alb/                  ALB, two target groups, path-based listener rule, S3 logs
    rds/                  RDS Postgres, managed secret, backups, enhanced monitoring
    ecs-cluster/          one Fargate cluster per environment
    ecs-service/          one reusable service definition (used for FE and BE)
    bastion/              Windows jump host + key pair generation + SSM
  environments/
    staging/              root module — staging sizing
    production/           root module — HA / production sizing
scripts/
  bootstrap.sh            runs the bootstrap step
  tf.sh                   init+plan+apply wrapper that fills in the S3 backend config
.github/workflows/
  ci.yml                  PRs: tests, scans, lint, tf fmt/validate, tf PLAN
  cd.yml                  push dev -> deploy staging; push main -> deploy production
monitoring/               two CloudWatch dashboards + Log Insights queries
docs/                     APPROACH.md, CHALLENGES.md
```

## Branch → environment mapping

| You push to… | What happens |
|--------------|--------------|
| `dev`        | build + scan + push images, then **deploy to staging** automatically |
| `main`       | build + scan + push images, then **deploy to production** — behind a required-reviewer approval gate |

The intended flow: merge work into `dev` (staging deploys, you test it), then open a
PR from `dev` into `main`; merging that runs the production deploy, which pauses for
manual approval before `terraform apply` touches prod.

## Setting this up from scratch

Prerequisites: Terraform ≥ 1.6, AWS CLI configured, Docker, Node 20.

### 1. Bootstrap first (once, manually)

This creates the things that must exist before — and outlive — any environment:
the remote-state S3 bucket, the DynamoDB lock table, and the two ECR repositories.
It uses **local** state, because you can't store the state backend's own state in a
backend that doesn't exist yet.

```bash
./scripts/bootstrap.sh
# or, by hand:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="project_name=8bytes-demo" -var="aws_region=us-east-1"
```

Note the outputs: `state_bucket`, `lock_table`, and the two ECR repo URLs.

You do **not** edit `backend.tf` by hand anymore. Each environment's `backend.tf`
is a *partial* config; the bucket and lock table names (which contain your account
id) are supplied at `terraform init` time. `scripts/tf.sh` computes and passes them
for you, and CI does the same.

### 2. Build and push an initial image for each tier (once)

After this, CI does it on every push. `<acct>` is your AWS account id.

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <acct>.dkr.ecr.us-east-1.amazonaws.com

docker build -t <acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-backend:bootstrap backend/
docker build -t <acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-frontend:bootstrap frontend/
docker push <acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-backend:bootstrap
docker push <acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-frontend:bootstrap
```

### 3. Set your office IP

Edit `office_cidrs` in `terraform/environments/<env>/terraform.tfvars` to your
office's public IP (e.g. `["203.0.113.10/32"]`). The bastion SG refuses `0.0.0.0/0`
by a validation rule, so this can't accidentally be left open.

### 4. Provision staging

```bash
./scripts/tf.sh staging apply \
  -var="frontend_image=<acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-frontend:bootstrap" \
  -var="backend_image=<acct>.dkr.ecr.us-east-1.amazonaws.com/8bytes-demo-backend:bootstrap"
```

Grab `alb_dns_name` from the output and open it — the UI loads and can add/list tasks
once the ECS services settle (a minute or two).

### 5. Repeat step 4 for production

```bash
./scripts/tf.sh production apply -var="frontend_image=..." -var="backend_image=..."
```

### 6. Wire up CI/CD

Create an IAM role for GitHub OIDC (trust policy scoped to this repo; permissions
scoped to ECR/ECS/Terraform actions — not `AdministratorAccess`), put its ARN in the
repo secret `AWS_DEPLOY_ROLE_ARN`, add `SLACK_WEBHOOK_URL` if you want failure
notifications, and add a required reviewer on the **production** GitHub Environment
(repo Settings → Environments → production). That reviewer requirement *is* the manual
approval gate — the workflow just references the environment name.

**Every value `ci.yml` / `cd.yml` reference, and where it comes from:**

| Name | Where it's set | Why |
|------|-----------------|-----|
| `AWS_DEPLOY_ROLE_ARN` | Repo secret (`secrets.AWS_DEPLOY_ROLE_ARN`) | Grants AWS access via OIDC - never a static access key, so it belongs in Secrets |
| `SLACK_WEBHOOK_URL` | Repo secret (`secrets.SLACK_WEBHOOK_URL`) | Posting to it lets anyone with the URL message the channel - treated as sensitive |
| `AWS_REGION` | Plain `env:` in the workflow file | Not sensitive - just a region name, fine to be visible in the YAML |
| `PROJECT_NAME` | Plain `env:` in the workflow file | Not sensitive - just a naming prefix |

Nothing else in either workflow is a credential, token, or otherwise sensitive value -
image tags, environment names, and the account ID (fetched at runtime via
`aws sts get-caller-identity`, never hardcoded) don't need to be secrets. If you add a
step that needs a new credential later, it goes in repo Settings → Secrets, the same
way as the two above - never as a plain `env:` value or a hardcoded string in the
workflow YAML.

## How the bastion key pair is generated

You asked specifically about this. The bastion module handles it two ways:

**Default (`create_key_pair = true`):** Terraform generates a 4096-bit RSA key with
the `tls` provider, uploads only the **public** half to EC2 as the key pair, and
stores the **private** half in Secrets Manager (KMS-encrypted). The private key is
never printed and never written to a laptop. To use it:

```bash
# fetch the private key
aws secretsmanager get-secret-value \
  --secret-id 8bytes-demo-staging-bastion-private-key \
  --query SecretString --output text > bastion.pem

# decrypt the Windows Administrator password
aws ec2 get-password-data --instance-id <id> --priv-launch-key bastion.pem \
  --query PasswordData --output text
```

Then RDP to the bastion's Elastic IP as `Administrator`. The trade-off: the private
key lands in Terraform state, which is exactly why state lives in the encrypted,
versioned, locked S3 backend.

**Alternative (`create_key_pair = false`):** create the key pair out-of-band so the
private key never touches state, and pass its name:

```bash
aws ec2 create-key-pair --key-name 8bytes-demo-bastion \
  --query KeyMaterial --output text > 8bytes-demo-bastion.pem
# then set create_key_pair = false and existing_key_name = "8bytes-demo-bastion"
```

**Best-practice note:** the bastion also has the SSM agent role attached, so you can
use **SSM Fleet Manager / Session Manager** to reach it with *no key pair and no open
RDP port at all*. RDP-over-office-IP is kept because the assignment asks for it, but
SSM is the more secure path if you want to drop the 3389 rule entirely.

## Security group design

Strict, directional chain — nothing skips a hop, and every source is a
security-group reference rather than a CIDR wherever the source is part of this stack:

- **ALB SG** — 80/443 from the internet. The only internet-facing SG.
- **frontend SG** — port 80 from the ALB SG, and from the bastion SG (admin).
- **backend SG** — port 3000 from the ALB SG (`/api/*`), from the frontend SG
  (direct service-to-service), and from the bastion SG (admin).
- **rds SG** — 5432 from the backend SG, and from the bastion SG (DB admin via psql/pgAdmin).
- **bastion SG** — 3389 (RDP) from `office_cidrs` **only**; a validation rule rejects
  `0.0.0.0/0`.

So the frontend, backend, and db talk to each other along the chain, the bastion can
reach all three, and the outside world can only reach the ALB and (from the office IP)
the bastion.

## Where `terraform apply` actually runs

- **CI (`ci.yml`, on PRs)** never applies. It runs `terraform fmt`, `terraform
  validate`, and **`terraform plan`** against the environment the PR targets, so the
  infra diff is visible in the PR before merge.
- **CD (`cd.yml`, on push/merge)** is where `terraform apply` runs — in the
  `deploy-staging` job (on push to `dev`) and the `deploy-production` job (on push to
  `main`, after approval). Each apply passes the freshly built `frontend_image` and
  `backend_image`, then forces a new ECS deployment for both services and waits for
  them to stabilize.

## Architecture decisions worth knowing about

- **One image built once per push, promoted as-is.** On a push, both images are built,
  scanned (Trivy, fails on fixable critical/high), and pushed tagged with the git SHA.
  The same tag flows into the `terraform apply` for that environment.
- **RDS credentials never touch Terraform state.** `manage_master_user_password = true`
  has RDS generate and own the secret in Secrets Manager. The backend task reads it via
  `secrets` at launch, so the password is never in the task def, in state, or in
  `docker inspect`.
- **Execution role vs task role are separate.** Execution role = what ECS needs to
  launch the container (pull image, write logs, read *only* the DB secret). Task role =
  what the app may do at runtime (empty today). The frontend gets no secret-read
  permission at all, because it has no secrets.
- **Staging and production are the same Terraform, different variables** — Multi-AZ,
  instance sizes, Fargate Spot, NAT-gateway count, and replica counts are all just
  variables, so the two environments can't structurally drift.
- **VPC CIDRs are per-environment** (`10.0.0.0/16` staging, `10.1.0.0/16` production)
  so the two VPCs could be peered later without overlap.

## Security considerations

- Frontend, backend, and database all run in private subnets with no public IP. Only
  the ALB (and the office-restricted bastion) are reachable from outside.
- Security groups are SG-to-SG references, not CIDRs, wherever the source is part of
  this stack.
- Secrets (DB credentials, bastion key) live in Secrets Manager, KMS-encrypted.
- IMDSv2 is required on the bastion; its root volume is encrypted.
- ECR scans images on push and tags are immutable.
- RDS is encrypted at rest, and `deletion_protection` is on in production.
- **Not done, needed before real traffic:** TLS on the ALB (ACM cert + 80→443
  redirect — currently plain HTTP), and a WAF in front of the ALB.

## Cost optimization measures

- Staging: single NAT gateway (vs one per AZ in prod), `FARGATE_SPOT` for both
  services, smaller RDS (`db.t4g.micro` Graviton), lower replica counts.
- Production: one NAT per AZ, on-demand Fargate, `db.t4g.small`, ≥2 replicas per tier.
- ALB access logs transition to IA after 30 days and expire after 90.
- ECR lifecycle policy keeps only the last 20 images per repo.
- RDS Performance Insights on the free 7-day retention tier.

## Backup strategy

- RDS automated backups: 3-day retention on staging, 14-day on production, in a
  low-traffic window.
- `deletion_protection = true` on production plus an automatic final snapshot on any
  deliberate teardown.
- Not implemented, worth adding for a real prod DB: cross-region snapshot copy.

## Alerting

`terraform/modules/alerting` provisions an SNS topic plus CloudWatch alarms across
every resource, wired into both environments already - nothing extra to apply.

**Threshold policy:** utilization-style metrics (CPU, memory, RDS storage used, RDS
connection pool usage) all alarm at **80%**, via `var.threshold_percent` (default 80,
override per-environment if needed). A few ALB metrics don't have a meaningful "80%"
reading and intentionally use their own static thresholds instead - each one is
commented in `terraform/modules/alerting/main.tf` explaining why:

| Alarm | Threshold | Why not 80%? |
|-------|-----------|---------------|
| ECS CPU / Memory (per service) | 80%, sustained 10 min | Naturally 0-100% - the standard case |
| RDS CPU | 80%, sustained 10 min | Same |
| RDS free storage | < 20% remaining (= 80% used) | Reported in bytes remaining, converted to the same 80%-used policy |
| RDS connections | 80% of an assumed 100-connection ceiling | Naturally a %-of-capacity metric |
| ALB unhealthy target count | ≥ 1, for 2 minutes | Not a utilization metric - any unhealthy target matters immediately |
| ALB p99 response time | > 2 seconds | A latency SLO, not a percentage |
| ALB 5xx count | ≥ 10 in 5 minutes | An absolute error count is more actionable than a % of low staging traffic |

**Getting notified:** set `alert_email` in either environment's `terraform.tfvars` (or
pass `-var="alert_email=you@example.com"`) and re-apply - that subscribes an email
address to the SNS topic. AWS sends a confirmation link on the next apply; alarms
won't reach you until you click it. To also notify Slack, subscribe an **AWS Chatbot**
Slack channel configuration to the same SNS topic ARN (`module.alerting.sns_topic_arn`)
- that's the standard AWS-native bridge, no custom Lambda forwarder needed.

## Importing the CloudWatch dashboards

`monitoring/dashboards/*.json` aren't applied by Terraform - they're meant to be
pasted directly into the CloudWatch console (**Dashboards → Create → View/edit
source**) or pushed via CLI:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name 8bytes-demo-infrastructure \
  --dashboard-body file://monitoring/dashboards/infrastructure-dashboard.json
```

Before doing either, replace the `PLACEHOLDER` value inside each JSON file with the
real ALB `arn_suffix` from `terraform output alb_arn_suffix` (in whichever environment
you're pointing the dashboard at) - the widgets show no data until that's a real ARN.
