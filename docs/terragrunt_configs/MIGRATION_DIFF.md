# Terragrunt Configuration Migration Guide

## Quick Reference: What Changed

### ECS IAM Roles Module

```diff
# terragrunt.hcl for ecs-task-role

terraform {
-  source = "git::ssh://git@bitbucket.jota.com:8899/terraform-ecs-iam-roles.git?ref=v0.7"
+  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-iam-roles.git?ref=v1.0"
}

inputs = {
   name             = "test-mota-ecs"
   short_name       = "test-meta"
   application_name = dependency.ecs-cluster.outputs.application_name
   
-  kms_key_id       = dependency.kms-key.outputs.kms_key_arn
+  kms_key_arn      = dependency.kms-key.outputs.kms_key_arn
   
   resource_owner   = "cloud"
   billing_entity   = "cloud"
+  billing_domain   = "cloud"
   security_domain  = "cloud"
   
+  # NEW REQUIRED VARIABLES
+  env                    = "prod"
+  aws_region_short_code  = "use1"
+  aws_account_aliases_v2 = {
+    "123456789012" = "prod"
+    "234567890123" = "staging"
+    "345678901234" = "dev"
+  }
   
   dynamic_policy = [...]
   tags = {...}
}
```

### ECS Scheduler Module

```diff
# terragrunt.hcl for ecs-scheduler

terraform {
-  source = "git::ssh://git@bitbucket.jota.com:8899/terraform-ecs-scheduler.git?ref=v0.3"
+  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-scheduler.git?ref=v1.0"
}

inputs = {
   application_name    = dependency.ecs-cluster.outputs.application_name
   schedule_expression = "cron(0 11 ? * WED *)"
   timezone            = "UTC"
   kms_key_arn         = dependency.kms-key-stack.outputs.kms_key_arn
   ecs_cluster_arn     = dependency.ecs-cluster.outputs.cluster_arn
   cluster_name        = dependency.ecs-cluster.outputs.cluster_short_name
   
-  security_group_id   = dependency.ecs-cluster.outputs.security_group_ids
+  security_group_ids  = dependency.ecs-cluster.outputs.security_group_ids
   
+  # NEW REQUIRED VARIABLES
+  trusted_compute_subnets = dependency.ecs-cluster.outputs.private_subnet_ids
+  aws_region_short_code   = "use1"
   
+  # NEW RECOMMENDED - Pass task role for PassRole permission
+  ecs_task_role_arn      = dependency.task_role.outputs.task_role_arn
+  ecs_execution_role_arn = dependency.task_role.outputs.execution_role_arn
   
   resource_owner      = "cloud"
   task_name           = dependency.task_role.outputs.name
   short_task_name     = dependency.task_role.outputs.short_name
   billing_domain      = "cloud"
   billing_entity      = "cloud"
   security_domain     = "cloud"
   
+  # NEW OPTIONAL - DLQ Alerting
+  enable_dlq_alarm  = true
+  dlq_alarm_actions = [dependency.sns-alerts.outputs.topic_arn]
}
```

---

## Variable Mapping Table

### ECS IAM Roles Module

| Old Variable (v0.7) | New Variable (v1.0) | Required | Notes |
|---------------------|---------------------|----------|-------|
| `kms_key_id` | `kms_key_arn` | ✅ | Renamed for clarity |
| `additonal_kms_key_ids` | `additional_kms_key_arns` | ❌ | Fixed typo |
| `managed_policies` | `task_role_managed_policies` | ❌ | Renamed for clarity |
| (none) | `env` | ✅ | **NEW REQUIRED** |
| (none) | `aws_region_short_code` | ✅ | **NEW REQUIRED** |
| (none) | `aws_account_aliases_v2` | ✅ | **NEW REQUIRED** |
| (none) | `billing_domain` | ❌ | New optional |
| (none) | `efs_file_system_arns` | ❌ | New optional |
| (none) | `s3_write_access` | ❌ | New optional |

### ECS Scheduler Module

| Old Variable (v0.3) | New Variable (v1.0) | Required | Notes |
|---------------------|---------------------|----------|-------|
| `security_group_id` | `security_group_ids` | ✅ | Changed from string to list |
| (none) | `trusted_compute_subnets` | ✅ | **NEW REQUIRED** |
| (none) | `aws_region_short_code` | ✅ | **NEW REQUIRED** |
| (none) | `ecs_task_role_arn` | ❌ | Recommended |
| (none) | `ecs_execution_role_arn` | ❌ | Recommended |
| (none) | `enable_dlq_alarm` | ❌ | Default: true |
| (none) | `dlq_alarm_actions` | ❌ | SNS topic ARNs |

---

## New Outputs Available

### ECS IAM Roles Module (NEW!)

The original module had **no outputs**. Now you can use:

```hcl
# In other modules:
dependency.task_role.outputs.task_role_arn        # ARN of task role
dependency.task_role.outputs.task_role_name       # Name of task role
dependency.task_role.outputs.execution_role_arn   # ARN of execution role
dependency.task_role.outputs.execution_role_name  # Name of execution role
dependency.task_role.outputs.name                 # Task name
dependency.task_role.outputs.short_name           # Short task name
```

### ECS Scheduler Module (NEW!)

```hcl
# Available outputs:
output.schedule_group_arn          # Schedule group ARN
output.schedule_arns               # Map of schedule ARNs
output.primary_schedule_arn        # Primary schedule ARN
output.dlq_arn                     # Dead letter queue ARN
output.dlq_url                     # Dead letter queue URL
output.scheduler_role_arn          # Scheduler IAM role ARN
output.dlq_messages_alarm_arn      # CloudWatch alarm ARN
```

---

## Migration Commands

```bash
# 1. Apply IAM Roles first (in each environment)
cd path/to/ecs-task-role
terragrunt plan   # Verify no unexpected destroys
terragrunt apply

# 2. Remove old policy attachment from scheduler state
cd path/to/ecs-scheduler
terragrunt state rm aws_iam_role_policy_attachment.ra 2>/dev/null || true

# 3. Apply Scheduler module
terragrunt plan   # Verify migrations look correct
terragrunt apply
```

---

## Verification Checklist

After migration, verify:

- [ ] `terragrunt plan` shows no unexpected changes
- [ ] IAM roles exist with new names (check AWS Console)
- [ ] Schedule appears in EventBridge Scheduler console
- [ ] DLQ exists in SQS console
- [ ] CloudWatch alarms exist (if enabled)
- [ ] Test: Manually trigger a schedule to verify task runs

