# Approach

Notes on how I worked through each part of the assignment, and why I made the calls I made.
The README covers the "what," this is more the "why" and "what I considered and didn't do."

## Part 1 - Infrastructure

Started from the network out rather than the compute in - got the VPC and subnet layout
right first, then security groups, then layered ALB/RDS/ECS on top. Doing it in the other
order (spin up compute first, retrofit networking) tends to produce security groups that
are wider than they need to be, because by the time you're adding them you're trying to
make something that already exists work, rather than designing the access pattern
up front.

Split into modules (vpc, security, alb, rds, ecs-cluster, ecs-service, bastion) instead of
one big root module with everything inline. The test I used: would I ever want to reuse this
piece with different inputs without touching the others? VPC and security groups, definitely -
RDS module without an ECS module attached is a completely reasonable thing to want for a
different project. ECS is deliberately split into `ecs-cluster` (one per environment) and a
reusable `ecs-service` (instantiated once for the frontend tier and once for the backend
tier) so the two services share one audited definition instead of two hand-written copies
that drift. Kept `environments/staging` and `environments/production` as the only two root
modules, both just wiring the five modules together with different variable values, so the
actual infrastructure shape can't drift between environments - only the sizing does.

The one piece I went back and forth on: single NAT gateway vs. one per AZ. Went with
"configurable, default differs by environment" rather than hardcoding either way, since
it's a real cost/resilience trade-off that depends on how much a staging outage actually
costs you (usually: not much) versus a production outage (usually: more than $32/month).

## Part 2 - CI/CD

Split into two workflows rather than one, because they answer different questions. `ci.yml`
answers "is this PR safe to merge" and never touches AWS. `cd.yml` answers "should this
already-merged code go live" and does. Keeping them separate means a broken AWS credential
or a flaky `terraform validate` never blocks someone from reviewing and merging a PR - CI
staying green is orthogonal to whether the deploy pipeline is healthy.

The deploy target is chosen by branch rather than by running both environments off one
branch: a push to `dev` deploys staging automatically, and a push to `main` deploys
production. That maps cleanly onto how the branches are already used - `dev` is the
integration branch you test on, `main` is what's live - and it means "promote to prod" is
just "merge dev into main," which is already a reviewed, auditable action.

For the approval gate, I used GitHub's built-in Environments feature (a "production"
environment with a required reviewer) rather than something homegrown like `workflow_dispatch`
with a manual trigger. It's less code, and it gives you an actual audit trail of who approved
what deploy, which `workflow_dispatch` doesn't give you for free.

Vulnerability scanning happens twice, on purpose, not as a copy-paste mistake: a filesystem/
dependency scan on PR (catches a bad `npm install` before it's even built into an image),
and an image scan after build on merge (catches anything introduced by the base image or
build process itself, which a dependency-only scan wouldn't see).

One thing I'd flag as a real limitation: the pipeline pushes one image tag (`github.sha`)
straight through staging and production with no rollback automation. If a production deploy
goes bad, the fix right now is "manually re-run the previous SHA's deploy job" - fine for
an assignment, not something I'd leave as-is for a real system without adding a scripted
rollback path.

## Part 3 - Monitoring & Logging

Went AWS-native (CloudWatch) rather than standing up Prometheus/Grafana, mainly because of
the time box - a self-hosted Prometheus stack is its own infrastructure project, and for one
service, CloudWatch gets you infra metrics for free (ECS, ALB, RDS all publish without any
extra agent or exporter). Application-level metrics are the one place this falls short out
of the box - I added a `/metrics` endpoint in Prometheus format so the app is ready for
either path, but didn't wire up the CloudWatch bridge for it inside the time available. That's
called out explicitly in the README rather than glossed over.

For logging, "centralized" ended up meaning three different destinations depending on the log
type, which felt more honest than forcing everything into one place: app logs go to CloudWatch
Logs via the `awslogs` driver (natural fit, ECS wires this up directly), VPC Flow Logs also go
to CloudWatch Logs (used as the "system logs" piece - shows accept/reject at the network level,
which is genuinely useful for debugging "why can't X reach Y" questions), and ALB access logs
go to S3 specifically because ALB can't write access logs anywhere else.

## Part 4 - Documentation

Wrote the README to be something I'd actually want to read at 2am during an incident, not a
sales pitch for the architecture - hence the "what's not done yet" sections in both the
security and monitoring parts of the README rather than presenting this as finished and
production-hardened. It isn't, and a README that pretends otherwise is worse than one that's
upfront about the gaps.

## Update — three-tier app + Windows bastion

The workload became a genuine three-tier app (frontend + backend + db) rather than a single
API, which fits a "frontend, backend, and database" use case better. The clean way to do
that on one ALB is path-based routing: `/` to the frontend target group, `/api/*` to the
backend target group. The browser then calls the API same-origin, so there's no CORS and the
backend is never directly exposed. The frontend, backend, and db form the same strict SG
chain the single-service version had, just with one more hop in front.

The Windows bastion was the other addition. Two decisions worth noting: (1) the RDP port is
locked to the office CIDR by a variable, with a validation rule that refuses `0.0.0.0/0`, so
"leave it open to the world" isn't a mistake you can make quietly; and (2) I attached the SSM
agent role anyway, so Fleet Manager / Session Manager works with no key pair and no open port
at all. RDP is there because it was asked for, but SSM is the path I'd actually push people
toward. The key pair itself is generated in Terraform (`tls_private_key` → `aws_key_pair`,
private half into Secrets Manager) with a `create_key_pair = false` escape hatch for teams
that would rather the private key never touch state.
