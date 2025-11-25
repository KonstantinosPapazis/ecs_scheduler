# ECS Scheduler Module - Technical Presentation

## Overview

This document provides a comprehensive overview of the ECS Scheduler Terraform module, explaining its architecture, security improvements, and usage patterns. Use this to present the module to your team.

---

## Table of Contents

1. [What Does This Module Do?](#what-does-this-module-do)
2. [Architecture Diagram](#architecture-diagram)
3. [Key Improvements Over Previous Version](#key-improvements-over-previous-version)
4. [Security Deep Dive](#security-deep-dive)
5. [Resource Inventory](#resource-inventory)
6. [Configuration Options](#configuration-options)
7. [Usage Examples](#usage-examples)
8. [Migration Guide](#migration-guide)
9. [Monitoring & Alerting](#monitoring--alerting)
10. [FAQ](#faq)

---

## What Does This Module Do?

The ECS Scheduler module creates **EventBridge Scheduler schedules** that automatically run ECS tasks on a defined schedule (cron or rate expressions).

### Use Cases

- 🕐 **Scheduled batch jobs** - Run data processing tasks at specific times
- 🔄 **Periodic maintenance** - Database cleanup, log rotation, etc.
- 📊 **Report generation** - Generate and send reports on schedule
- 🔍 **Health checks** - Run periodic health check tasks
- 📦 **Data synchronization** - Sync data between systems on schedule

### Why EventBridge Scheduler (Not CloudWatch Events)?

| Feature | EventBridge Scheduler ✅ | CloudWatch Events Rules ❌ |
|---------|-------------------------|---------------------------|
| Retry policy | Configurable (0-185 retries) | None |
| Dead letter queue | Native support | Manual setup |
| Flexible time window | Yes (1-1440 min) | No |
| Timezone support | Full timezone support | UTC only |
| One-time schedules | Yes (with auto-delete) | No |
| Maximum schedules | 1,000,000 per account | 300 per account |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ECS SCHEDULER MODULE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────┐                                                     │
│  │  Schedule Group    │                                                     │
│  │  (Organization)    │                                                     │
│  └─────────┬──────────┘                                                     │
│            │                                                                 │
│            ▼                                                                 │
│  ┌────────────────────┐         ┌─────────────────┐                        │
│  │  Schedule(s)       │────────▶│  IAM Role       │                        │
│  │  - Cron/Rate       │         │  (Least         │                        │
│  │  - Timezone        │         │   Privilege)    │                        │
│  │  - Retry Policy    │         └────────┬────────┘                        │
│  └─────────┬──────────┘                  │                                  │
│            │                              │                                  │
│            │ On Schedule                  │ AssumeRole                       │
│            ▼                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │                    TARGET: ECS Cluster                       │           │
│  │  ┌─────────────────┐                                        │           │
│  │  │  RunTask API    │───▶ Task Definition ───▶ Running Task  │           │
│  │  └─────────────────┘                                        │           │
│  └─────────────────────────────────────────────────────────────┘           │
│            │                                                                 │
│            │ On Failure (after retries)                                     │
│            ▼                                                                 │
│  ┌────────────────────┐         ┌─────────────────┐                        │
│  │  SQS Dead Letter   │────────▶│  CloudWatch     │                        │
│  │  Queue (DLQ)       │         │  Alarm          │──▶ SNS ──▶ Alert      │
│  │  - KMS Encrypted   │         │  (Messages > 0) │                        │
│  │  - Restricted      │         └─────────────────┘                        │
│  └────────────────────┘                                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Improvements Over Previous Version

### 1. Security Enhancements

| Aspect | Before (v1) | After (v2) | Risk Reduction |
|--------|-------------|------------|----------------|
| IAM Policy | `AmazonECS_FullAccess` (50+ actions) | 6 specific actions | 🔴 → 🟢 Critical |
| Resource Scope | `Resource: "*"` | Specific ARNs only | 🔴 → 🟢 Critical |
| SQS Access | Open | Restricted to Scheduler only | 🟡 → 🟢 High |
| SSL Enforcement | None | Deny non-SSL on DLQ | 🟡 → 🟢 High |
| Permissions Boundary | Not supported | Supported | 🟡 → 🟢 Medium |

### 2. Operational Improvements

| Feature | Before (v1) | After (v2) |
|---------|-------------|------------|
| Retry configuration | Hardcoded (5 retries) | Configurable (0-185) |
| Event age limit | Not set | Configurable (60-86400s) |
| DLQ monitoring | None | CloudWatch alarms |
| Multiple schedules | Basic support | Full support with per-schedule config |
| Timezone handling | Basic | Full timezone support |
| Schedule boundaries | None | Start/end date support |

### 3. Code Quality Improvements

| Aspect | Before (v1) | After (v2) |
|--------|-------------|------------|
| Policy definition | Inline `jsonencode()` | `aws_iam_policy_document` data sources |
| Variable validation | None | Comprehensive validations |
| Documentation | Minimal | Full README + inline comments |
| Outputs | Basic | Comprehensive (ARNs, names, URLs) |
| Backward compatibility | N/A | `moved` blocks for safe migration |

---

## Security Deep Dive

### IAM Policy Comparison

#### ❌ BEFORE: Overly Permissive

```hcl
# Attached AmazonECS_FullAccess which grants:
{
  "Effect": "Allow",
  "Action": [
    "ecs:*",                    # ALL 50+ ECS actions
    "elasticloadbalancing:*",   # ALL load balancer actions
    "cloudwatch:*",             # ALL CloudWatch actions  
    "logs:*",                   # ALL CloudWatch Logs actions
    "servicediscovery:*",       # ALL service discovery actions
    "application-autoscaling:*" # ALL auto-scaling actions
  ],
  "Resource": "*"               # On ALL resources in account
}
```

**Risk:** If credentials leaked, attacker could:
- Delete ECS clusters
- Modify services
- Access any ECS resource
- Manipulate load balancers
- Delete CloudWatch alarms

#### ✅ AFTER: Least Privilege

```hcl
# Only the permissions actually needed:

# 1. Run tasks (scoped to specific task definition + cluster)
statement {
  actions   = ["ecs:RunTask"]
  resources = ["${task_definition_arn}", "${task_definition_arn}:*"]
  condition {
    test     = "ArnEquals"
    variable = "ecs:cluster"
    values   = [cluster_arn]  # Only on THIS cluster
  }
}

# 2. Tag resources (scoped + conditional)
statement {
  actions   = ["ecs:TagResource"]
  resources = [cluster_arn, "task/${cluster_name}/*"]
  condition {
    test     = "StringEquals"
    variable = "ecs:CreateAction"
    values   = ["RunTask"]  # Only when creating via RunTask
  }
}

# 3. Send to DLQ (scoped to specific queue)
statement {
  actions   = ["sqs:SendMessage"]
  resources = [dlq_arn]  # Only THIS queue
}

# 4. KMS operations (scoped + service-restricted)
statement {
  actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
  resources = [kms_key_arn]
  condition {
    test     = "StringEquals"
    variable = "kms:ViaService"
    values   = ["sqs.region.amazonaws.com", "scheduler.region.amazonaws.com"]
  }
}

# 5. Pass role (scoped + service-restricted)
statement {
  actions   = ["iam:PassRole"]
  resources = [task_role_arn]
  condition {
    test     = "StringEquals"
    variable = "iam:PassedToService"
    values   = ["ecs-tasks.amazonaws.com"]
  }
}
```

**Risk with new policy:** If credentials leaked, attacker can ONLY:
- Run tasks using the specific task definition
- On the specific cluster
- Nothing else

### SQS DLQ Security

```hcl
# DLQ Policy enforces:

# 1. Only EventBridge Scheduler can send messages
statement {
  principals {
    type        = "Service"
    identifiers = ["scheduler.amazonaws.com"]
  }
  actions   = ["sqs:SendMessage"]
  condition {
    test     = "ArnLike"
    variable = "aws:SourceArn"
    values   = ["arn:aws:scheduler:*:*:schedule/${schedule_group}/*"]
  }
}

# 2. Deny non-SSL access
statement {
  effect = "Deny"
  principals {
    type        = "*"
    identifiers = ["*"]
  }
  actions = ["sqs:*"]
  condition {
    test     = "Bool"
    variable = "aws:SecureTransport"
    values   = ["false"]
  }
}
```

---

## Resource Inventory

| Resource Type | Resource Name | Purpose |
|---------------|---------------|---------|
| `aws_scheduler_schedule_group` | `ecs` | Groups related schedules |
| `aws_scheduler_schedule` | `ecs[""]` + additional | Defines when tasks run |
| `aws_iam_role` | `scheduler` | Identity for EventBridge Scheduler |
| `aws_iam_role_policy` | `scheduler` | Permissions for the role |
| `aws_sqs_queue` | `dlq` | Captures failed invocations |
| `aws_sqs_queue_policy` | `dlq` | Restricts DLQ access |
| `aws_cloudwatch_metric_alarm` | `dlq_messages_visible` | Alerts on failures |
| `aws_cloudwatch_metric_alarm` | `dlq_oldest_message` | Alerts on unprocessed failures |

---

## Configuration Options

### Required Variables

```hcl
module "ecs_scheduler" {
  source = "..."

  # Cluster & Task
  cluster_name        = "my-cluster"
  ecs_cluster_arn     = "arn:aws:ecs:us-east-1:123456789:cluster/my-cluster"
  task_name           = "my-task"
  
  # Schedule
  schedule_expression = "rate(1 hour)"  # or cron(0 9 * * ? *)
  
  # Network
  trusted_compute_subnets = ["subnet-abc", "subnet-def"]
  security_group_ids      = ["sg-123"]
  
  # Security
  kms_key_arn = "arn:aws:kms:..."
  
  # Naming (company standard)
  resource_owner        = "platform-team"
  billing_entity        = "engineering"
  billing_domain        = "infrastructure"
  security_domain       = "internal"
  aws_region_short_code = "use1"
}
```

### Optional Variables (Highlights)

| Variable | Default | Description |
|----------|---------|-------------|
| `enabled` | `true` | Enable/disable schedule |
| `timezone` | `"UTC"` | Timezone for schedule |
| `launch_type` | `"FARGATE"` | FARGATE, EC2, or EXTERNAL |
| `task_count` | `1` | Tasks to run (1-10) |
| `maximum_retry_attempts` | `5` | Retries before DLQ (0-185) |
| `enable_dlq_alarm` | `true` | Create CloudWatch alarms |
| `dlq_alarm_actions` | `[]` | SNS topics for alerts |
| `permissions_boundary_arn` | `null` | IAM permissions boundary |

---

## Usage Examples

### Basic Scheduled Task

```hcl
module "daily_report" {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-scheduler.git?ref=v2"

  cluster_name            = "production"
  ecs_cluster_arn         = data.aws_ecs_cluster.main.arn
  task_name               = "daily-report"
  schedule_expression     = "cron(0 6 * * ? *)"  # 6 AM daily
  timezone                = "America/New_York"
  trusted_compute_subnets = data.aws_subnets.private.ids
  security_group_ids      = [aws_security_group.ecs_tasks.id]
  kms_key_arn             = aws_kms_key.main.arn
  
  # Alerting
  enable_dlq_alarm  = true
  dlq_alarm_actions = [aws_sns_topic.alerts.arn]
  
  # Naming
  resource_owner        = "data-team"
  billing_entity        = "analytics"
  billing_domain        = "reporting"
  security_domain       = "internal"
  aws_region_short_code = "use1"
}
```

### Multiple Schedules for Same Task

```hcl
module "multi_schedule" {
  source = "..."

  # Primary schedule
  schedule_expression = "cron(0 9 * * ? *)"  # 9 AM weekdays
  
  # Additional schedules
  additional_schedules = [
    {
      name                = "evening"
      schedule_expression = "cron(0 18 * * ? *)"  # 6 PM
    },
    {
      name                = "weekend"
      schedule_expression = "cron(0 12 ? * SAT,SUN *)"  # Noon on weekends
      overrides = jsonencode({
        containerOverrides = [{
          name = "main"
          environment = [{ name = "WEEKEND", value = "true" }]
        }]
      })
    }
  ]
}
```

---

## Migration Guide

### From v1 to v2

1. **No action needed for resource renames** - `moved` blocks handle this automatically

2. **Review plan output** - Look for:
   - `~ update` for existing resources getting new attributes
   - `- destroy` for `aws_iam_role_policy_attachment.ra` (expected!)

3. **Remove old policy attachment from state** (if exists):
   ```bash
   terraform state rm module.scheduler.aws_iam_role_policy_attachment.ra
   ```

4. **Update variable usage** (if using deprecated variable):
   ```hcl
   # Before
   security_group_id = "sg-123"
   
   # After (recommended)
   security_group_ids = ["sg-123"]
   ```

---

## Monitoring & Alerting

### CloudWatch Alarms

The module creates two alarms:

| Alarm | Metric | Triggers When |
|-------|--------|---------------|
| DLQ Messages | `ApproximateNumberOfMessagesVisible` | Any message in DLQ |
| DLQ Age | `ApproximateAgeOfOldestMessage` | Message older than 1 hour |

### Alert Flow

```
Schedule Fails → DLQ → CloudWatch Alarm → SNS → Email/Slack/PagerDuty
```

### Recommended Alert Configuration

```hcl
# Create SNS topic for alerts
resource "aws_sns_topic" "ecs_scheduler_alerts" {
  name = "ecs-scheduler-alerts"
}

# Email subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.ecs_scheduler_alerts.arn
  protocol  = "email"
  endpoint  = "team@company.com"
}

# Use in module
module "scheduler" {
  # ...
  dlq_alarm_actions = [aws_sns_topic.ecs_scheduler_alerts.arn]
  dlq_ok_actions    = [aws_sns_topic.ecs_scheduler_alerts.arn]
}
```

---

## FAQ

### Q: Why not use ECS Scheduled Tasks (in ECS console)?

**A:** Those use CloudWatch Events Rules under the hood, which:
- Have no built-in retry mechanism
- No dead letter queue support
- Limited to 300 rules per account
- UTC timezone only

EventBridge Scheduler is the newer, more capable service.

### Q: What happens when a scheduled task fails?

**A:** 
1. Scheduler retries (up to `maximum_retry_attempts` times)
2. If all retries fail, event goes to DLQ
3. CloudWatch alarm triggers
4. You receive notification via SNS

### Q: Can I run multiple tasks per schedule?

**A:** Yes, set `task_count = N` (max 10). All tasks run simultaneously.

### Q: Where do I see my schedules in AWS Console?

**A:** Amazon EventBridge → Scheduler → Schedules (NOT in ECS Scheduled Tasks)

### Q: Is there downtime during migration from v1 to v2?

**A:** No. The `moved` blocks ensure resources are renamed in state without recreation.

---

## Summary

| Aspect | v1 (Original) | v2 (Improved) |
|--------|---------------|---------------|
| **Security** | ❌ Over-permissive | ✅ Least privilege |
| **Monitoring** | ❌ None | ✅ CloudWatch alarms |
| **Configuration** | ❌ Limited | ✅ Comprehensive |
| **Documentation** | ❌ Minimal | ✅ Complete |
| **Best Practices** | ❌ Some gaps | ✅ AWS Well-Architected |

---

## Questions?

Contact: [Your Team Name]
Repository: [Your Bitbucket URL]

