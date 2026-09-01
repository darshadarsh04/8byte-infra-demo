# Useful CloudWatch Logs Insights queries

Quick reference for the three log groups this stack produces. Paste the query into
Logs Insights, pick the log group, run.

## Application errors (`/ecs/8bytes-demo-<env>`)

```
fields @timestamp, @message
| filter @message like /error|Error|ERROR/
| sort @timestamp desc
| limit 50
```

## Slow DB queries (`/aws/rds/instance/8bytes-demo-<env>-db/postgresql`)

Requires `log_min_duration_statement` from the RDS parameter group, which is
set to 500ms in `terraform/modules/rds/main.tf`.

```
fields @timestamp, @message
| filter @message like /duration:/
| sort @timestamp desc
| limit 50
```

## VPC Flow Logs - rejected connections (`/aws/vpc/8bytes-demo-<env>-flow-logs`)

Useful for confirming the security group chain is actually doing what we think -
should return nothing except noise from health checks / port scans, never
anything from an unexpected source into RDS.

```
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 50
```

## ALB 5xx spike correlation

Cross-reference against the application dashboard's error rate widget - if
this and the app error log both spike at the same timestamp, it's the app;
if only this spikes, it's more likely a target health/timeout issue.

```
fields @timestamp, elb_status_code, target_status_code, request_processing_time, target_processing_time
| filter elb_status_code >= 500
| sort @timestamp desc
| limit 50
```
