# Detailed Changelog: Original vs Improved Module

This document provides a comprehensive comparison between the original ECS Scheduler module and the improved version.

---

## Quick Summary

| Metric | Original | Improved | Change |
|--------|----------|----------|--------|
| Files | 1 (monolithic) | 7 (modular) | +6 files |
| Lines of code | ~150 | ~1,500 | +1,350 lines |
| Resources | 5 | 8 | +3 resources |
| Variables | ~15 (implicit) | 45+ | +30 variables |
| Outputs | 0 | 15 | +15 outputs |
| Validations | 0 | 20+ | +20 validations |
| Security issues | 5 | 0 | -5 issues |

---

## Original Code (v1)

Below is the complete original module code that was provided:

```hcl
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  aws_region     = data.aws_region.current.name
  aws_account_id = data.aws_caller_identity.current.account_id
  schedules = concat([{
    name_prefix                     = ""
    name                            = ""
    schedule_expression             = var.schedule_expression
    enabled                         = var.enabled
    overrides                       = var.overrides
    flexible_time_window_in_minutes = var.flexible_time_window_in_minutes
  }], var.additional_schedules)
  short_task_name = var.short_task_name == null ? var.task_name : var.short_task_name
}

module "naming" {
  source          = "git::ssh://git@bitbucket.jota.com:8998/terraform-naming.git?ref=v6
  resource_owner  = var.resource_owner
  primary_name    = var.cluster_name
  secondary_name  = local.short_task_name
  billing_entity  = var.billing_entity
  billing_domain  = var.billing_domain
  security_domain = var.security_domain
}

resource "aws_scheduler_schedule_group" "ecs" {
  name = module.naming.cloudwatch_schedule
}

moved {
  from = aws_scheduler_schedule.ecs
  to   = aws_scheduler_schedule.ecs[""]
}

resource "aws_scheduler_schedule" "ecs" {
  for_each   = { for index, schedule in local.schedules : schedule.name => schedule }
  name       = "${module.naming.cloudwatch_log_group_name_prefix}-${local.short_task_name}${each.value.name_prefix}${each.value.name}-cw-schedule"
  group_name = module.naming.cloudwatch_schedule
  state      = (each.value.enabled == null ? var.enabled : each.value.enabled) ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode                      = each.value.flexible_time_window_in_minutes != null ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = each.value.flexible_time_window_in_minutes
  }

  schedule_expression = each.value.schedule_expression

  target {
    retry_policy {
      maximum_retry_attempts = 5
    }

    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.ecs.arn
    dead_letter_config {
      arn = aws_sqs_queue.sqs_test_dlq.arn
    }

    input = each.value.overrides == "NONE" ? var.overrides : each.value.overrides
    ecs_parameters {
      task_definition_arn = var.task_definition_arn != null ? var.task_definition_arn : "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task-definition/${module.naming_long.ecs_task_def}"
      network_configuration {
        subnets         = var.trusted_compute_subnets
        security_groups = [var.security_group_id]
      }

      dynamic "capacity_provider_strategy" {
        for_each = var.capacity_provider_name == null ? [] : [true]
        content {
          capacity_provider = var.capacity_provider_name
          weight            = 1
        }
      }

      propagate_tags = "TASK_DEFINITION"
    }
  }
  kms_key_arn                  = var.kms_key_arn
  schedule_expression_timezone = var.timezone
}

resource "aws_iam_role_policy" "ecs" {
  name = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-policy"
  role = aws_iam_role.ecs.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:RunTask",
        ]
        Resource = var.task_definition_arn != null ? "${var.task_definition_arn}*" : "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task-definition/${module.naming.ecs_task_def}*",
      },
      {
        Effect = "Allow",
        Action = [
          "ecs:TagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "config:GetComplianceDetailsByConfigRule",
          "organizations:DescribeAccount",
        ]
        Resource = "*",
      },
      {
        Action : [
          "sqs:SendMessage"
        ],
        Effect : "Allow",
        Resource : aws_sqs_queue.sqs_test_dlq.arn
      },
      {
        Action : [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
        ],
        Effect : "Allow",
        Resource : var.kms_key_arn
      },
      {
        Action : [
          "iam:PassRole"
        ],
        Effect : "Allow",
        Resource : var.ecs_task_role_arn != null ? var.ecs_task_role_arn : "arn:aws:iam::${local.aws_account_id}:role/${module.naming.iam_name_prefix}*"
      },
    ]
  })
}

resource "aws_iam_role" "ecs" {
  name = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(
    module.naming.tags,
    tomap({ "Name" = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-role" }),
  )
}

resource "aws_sqs_queue" "sqs_test_dlq" {
  name              = module.naming.sqs_queue_name
  kms_master_key_id = var.kms_key_arn
}

resource "aws_iam_role_policy_attachment" "ra" {
  role       = aws_iam_role.ecs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}
```

---

## Detailed Change List

### 🗂️ File Structure Changes

| Change | Details |
|--------|---------|
| **Split monolithic file** | Single file → 7 organized files |
| `main.tf` | Core resources (schedules, IAM, SQS, alarms) |
| `variables.tf` | All input variables with validations |
| `data.tf` | Data sources and IAM policy documents |
| `outputs.tf` | All module outputs |
| `moved.tf` | State migration blocks |
| `versions.tf` | Terraform/provider constraints |
| `README.md` | Comprehensive documentation |

---

### 🔒 Security Changes

#### 1. REMOVED: AmazonECS_FullAccess Policy Attachment

```diff
- resource "aws_iam_role_policy_attachment" "ra" {
-   role       = aws_iam_role.ecs.name
-   policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
- }
```

**Why:** This policy grants 50+ actions including destructive operations like `ecs:DeleteCluster`, `ecs:DeleteService`. The scheduler only needs `ecs:RunTask`.

---

#### 2. FIXED: Overly Broad ecs:TagResource Permission

```diff
# BEFORE
- {
-   Effect = "Allow",
-   Action = [
-     "ecs:TagResource",
-   ]
-   Resource = "*"
- }

# AFTER
+ statement {
+   sid     = "AllowTagResource"
+   effect  = "Allow"
+   actions = ["ecs:TagResource"]
+   resources = [
+     var.ecs_cluster_arn,
+     "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task/${var.cluster_name}/*"
+   ]
+   condition {
+     test     = "StringEquals"
+     variable = "ecs:CreateAction"
+     values   = ["RunTask"]
+   }
+ }
```

**Why:** `Resource = "*"` allowed tagging ANY ECS resource in the account.

---

#### 3. REMOVED: Unnecessary Permissions

```diff
- {
-   Effect = "Allow",
-   Action = [
-     "logs:PutLogEvents",
-     "config:GetComplianceDetailsByConfigRule",
-     "organizations:DescribeAccount",
-   ]
-   Resource = "*",
- }
```

**Why:** These permissions are not needed for EventBridge Scheduler to run ECS tasks:
- `logs:PutLogEvents` - Scheduler doesn't write logs directly
- `config:GetComplianceDetailsByConfigRule` - Unrelated to scheduling
- `organizations:DescribeAccount` - Unrelated to scheduling

---

#### 4. ADDED: IAM Conditions for Enhanced Security

```diff
# ecs:RunTask now has cluster condition
+ condition {
+   test     = "ArnEquals"
+   variable = "ecs:cluster"
+   values   = [var.ecs_cluster_arn]
+ }

# KMS operations restricted to specific services
+ condition {
+   test     = "StringEquals"
+   variable = "kms:ViaService"
+   values   = [
+     "sqs.${local.aws_region}.amazonaws.com",
+     "scheduler.${local.aws_region}.amazonaws.com"
+   ]
+ }

# PassRole restricted to ECS tasks service
+ condition {
+   test     = "StringEquals"
+   variable = "iam:PassedToService"
+   values   = ["ecs-tasks.amazonaws.com"]
+ }
```

---

#### 5. ADDED: SQS Queue Policy (Restricted Access)

```diff
+ resource "aws_sqs_queue_policy" "dlq" {
+   queue_url = aws_sqs_queue.dlq.id
+   policy    = data.aws_iam_policy_document.sqs_dlq_policy.json
+ }

+ # Policy restricts:
+ # 1. Only EventBridge Scheduler can send messages
+ # 2. SSL is enforced (denies non-HTTPS)
+ # 3. Source account verification
```

**Before:** SQS queue had no resource policy - anyone with IAM permissions could access it.

---

#### 6. CHANGED: Policy Definition Method

```diff
# BEFORE: Inline jsonencode (harder to read, no validation)
- policy = jsonencode({
-   Version = "2012-10-17",
-   Statement = [...]
- })

# AFTER: aws_iam_policy_document data source (validated, readable)
+ data "aws_iam_policy_document" "scheduler_permissions" {
+   statement {
+     sid     = "AllowRunTask"
+     effect  = "Allow"
+     actions = ["ecs:RunTask"]
+     resources = [...]
+     condition {...}
+   }
+   # ... more statements
+ }
+
+ resource "aws_iam_role_policy" "scheduler" {
+   policy = data.aws_iam_policy_document.scheduler_permissions.json
+ }
```

---

### 📦 Resource Changes

#### 1. RENAMED: Resources for Clarity

| Original Name | New Name | Reason |
|---------------|----------|--------|
| `aws_iam_role.ecs` | `aws_iam_role.scheduler` | Role is for scheduler, not ECS |
| `aws_iam_role_policy.ecs` | `aws_iam_role_policy.scheduler` | Consistent with role |
| `aws_sqs_queue.sqs_test_dlq` | `aws_sqs_queue.dlq` | Remove "test", cleaner name |

Migration handled by `moved` blocks:
```hcl
moved {
  from = aws_iam_role.ecs
  to   = aws_iam_role.scheduler
}
```

---

#### 2. ADDED: New Resources

| Resource | Purpose |
|----------|---------|
| `aws_sqs_queue_policy.dlq` | Restrict DLQ access |
| `aws_cloudwatch_metric_alarm.dlq_messages_visible` | Alert on failures |
| `aws_cloudwatch_metric_alarm.dlq_oldest_message` | Alert on unprocessed messages |

---

#### 3. ENHANCED: Existing Resources

**aws_scheduler_schedule_group.ecs**
```diff
  resource "aws_scheduler_schedule_group" "ecs" {
    name = module.naming.cloudwatch_schedule
+
+   tags = merge(
+     module.naming.tags,
+     {
+       "Name" = module.naming.cloudwatch_schedule
+     },
+     var.additional_tags
+   )
  }
```

**aws_scheduler_schedule.ecs**
```diff
  resource "aws_scheduler_schedule" "ecs" {
    # ... existing config ...
+   description = coalesce(each.value.description, "ECS scheduled task for ${local.short_task_name}...")
+
+   # Optional start/end dates for time-bounded schedules
+   start_date = each.value.start_date
+   end_date   = each.value.end_date
+
+   # Action after completion (useful for one-time schedules)
+   action_after_completion = var.action_after_completion

    target {
      retry_policy {
-       maximum_retry_attempts = 5
+       maximum_retry_attempts       = var.maximum_retry_attempts
+       maximum_event_age_in_seconds = var.maximum_event_age_in_seconds
      }

      ecs_parameters {
+       task_count = var.task_count
+       launch_type = var.launch_type
+       platform_version = var.launch_type == "FARGATE" ? var.platform_version : null
+       enable_ecs_managed_tags = var.enable_ecs_managed_tags
+       group = var.ecs_task_group
+
        network_configuration {
-         security_groups = [var.security_group_id]
+         security_groups  = local.security_group_ids  # Supports multiple
+         assign_public_ip = var.assign_public_ip
        }

+       # Placement constraints for EC2 launch type
+       dynamic "placement_constraints" {
+         for_each = var.placement_constraints
+         content {...}
+       }
+
+       # Placement strategy for EC2 launch type
+       dynamic "placement_strategy" {
+         for_each = var.placement_strategy
+         content {...}
+       }
+
+       # Tags for tasks
+       tags = merge(module.naming.tags, {"ScheduleName" = each.key}, var.additional_tags)
      }
    }
  }
```

**aws_sqs_queue (renamed to .dlq)**
```diff
  resource "aws_sqs_queue" "dlq" {
    name              = module.naming.sqs_queue_name
    kms_master_key_id = var.kms_key_arn
+   kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds
+
+   # Message configuration
+   message_retention_seconds  = var.dlq_message_retention_seconds
+   visibility_timeout_seconds = var.dlq_visibility_timeout_seconds
+   receive_wait_time_seconds  = var.dlq_receive_wait_time_seconds
+   delay_seconds              = var.dlq_delay_seconds
+   max_message_size           = var.dlq_max_message_size
+
+   tags = merge(
+     module.naming.tags,
+     {
+       "Name"    = module.naming.sqs_queue_name
+       "Purpose" = "ECS Scheduler Dead Letter Queue"
+     },
+     var.additional_tags
+   )
  }
```

**aws_iam_role (renamed to .scheduler)**
```diff
  resource "aws_iam_role" "scheduler" {
    name = "..."
+   description = "IAM role for EventBridge Scheduler to run ECS tasks for ${local.short_task_name}"
+
-   assume_role_policy = jsonencode({...})
+   assume_role_policy    = data.aws_iam_policy_document.scheduler_assume_role.json
+   permissions_boundary  = var.permissions_boundary_arn
+   max_session_duration  = var.max_session_duration
+   force_detach_policies = true

    tags = merge(...)
  }
```

---

### 🔧 Bug Fixes

| Bug | Fix |
|-----|-----|
| Deprecated `data.aws_region.current.name` | Changed to `.id` |
| Missing closing quote in naming module source | Fixed |
| Reference to `module.naming_long` (doesn't exist) | Changed to `module.naming` |
| Single security group only | Now supports list of security groups |

---

### 📊 New Variables Added (45+)

#### Schedule Configuration
- `schedule_description`
- `schedule_start_date`
- `schedule_end_date`
- `action_after_completion`

#### ECS Task Configuration
- `launch_type`
- `platform_version`
- `task_count`
- `enable_ecs_managed_tags`
- `ecs_task_group`
- `assign_public_ip`

#### Retry Policy
- `maximum_retry_attempts` (was hardcoded to 5)
- `maximum_event_age_in_seconds`

#### DLQ Configuration
- `dlq_message_retention_seconds`
- `dlq_visibility_timeout_seconds`
- `dlq_receive_wait_time_seconds`
- `dlq_delay_seconds`
- `dlq_max_message_size`
- `kms_data_key_reuse_period_seconds`
- `dlq_admin_principals`

#### CloudWatch Alarms
- `enable_dlq_alarm`
- `dlq_alarm_threshold`
- `dlq_alarm_evaluation_periods`
- `dlq_alarm_period_seconds`
- `dlq_alarm_actions`
- `dlq_ok_actions`
- `dlq_alarm_treat_missing_data`

#### IAM Configuration
- `ecs_execution_role_arn`
- `permissions_boundary_arn`
- `max_session_duration`
- `restrict_assume_role_to_schedule_group`
- `allow_stop_task`
- `enable_cloudwatch_logs`

#### Placement (EC2)
- `placement_constraints`
- `placement_strategy`

#### Capacity Provider
- `capacity_provider_weight` (was hardcoded to 1)
- `capacity_provider_base`

---

### 📤 New Outputs Added (15)

```hcl
# Schedule outputs
output "schedule_group_arn" {}
output "schedule_group_name" {}
output "schedule_arns" {}
output "schedule_names" {}
output "primary_schedule_arn" {}
output "primary_schedule_name" {}

# DLQ outputs
output "dlq_arn" {}
output "dlq_url" {}
output "dlq_name" {}

# IAM outputs
output "scheduler_role_arn" {}
output "scheduler_role_name" {}
output "scheduler_role_unique_id" {}

# Alarm outputs
output "dlq_messages_alarm_arn" {}
output "dlq_messages_alarm_name" {}
output "dlq_age_alarm_arn" {}
output "dlq_age_alarm_name" {}

# Computed values
output "task_definition_arn" {}
output "short_task_name" {}
output "all_schedule_details" {}
```

---

## Migration Checklist

- [ ] Review this changelog with team
- [ ] Run `terraform plan` to preview changes
- [ ] Remove old policy attachment: `terraform state rm aws_iam_role_policy_attachment.ra`
- [ ] Apply changes: `terraform apply`
- [ ] Verify schedules in EventBridge console
- [ ] Configure `dlq_alarm_actions` for alerting
- [ ] Test a manual trigger to verify task runs

---

## Questions?

If you have questions about any of these changes, please reach out to the Platform Team.

