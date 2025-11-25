# ECS Scheduled Task Module

This Terraform module creates EventBridge Scheduler schedules to run ECS tasks on a defined schedule with proper IAM roles, dead-letter queues, and security configurations following AWS best practices.

## Features

- ✅ **EventBridge Scheduler** - Uses the new EventBridge Scheduler (not CloudWatch Events Rules)
- ✅ **Least Privilege IAM** - Tightly scoped IAM policies following AWS best practices
- ✅ **Dead Letter Queue** - SQS DLQ for failed schedule invocations with restricted access
- ✅ **KMS Encryption** - Full encryption support for schedules and queues
- ✅ **Multiple Schedules** - Support for multiple schedules targeting the same task
- ✅ **Flexible Configuration** - Support for Fargate, EC2, and capacity providers
- ✅ **Placement Strategies** - Configurable placement constraints and strategies for EC2

## Usage

### Basic Example (Fargate)

```hcl
module "ecs_scheduler" {
  source = "path/to/ecs_scheduler"

  # Required
  cluster_name            = "my-cluster"
  ecs_cluster_arn         = "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"
  task_name               = "my-scheduled-task"
  schedule_expression     = "rate(1 hour)"
  trusted_compute_subnets = ["subnet-abc123", "subnet-def456"]
  kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

  # Naming module requirements
  resource_owner        = "platform-team"
  billing_entity        = "engineering"
  billing_domain        = "infrastructure"
  security_domain       = "internal"
  aws_region_short_code = "use1"

  # Optional - Security groups
  security_group_ids = ["sg-abc123"]

  # Optional - Tags
  additional_tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```

### Example with Multiple Schedules

```hcl
module "ecs_scheduler" {
  source = "path/to/ecs_scheduler"

  # ... required variables ...

  schedule_expression = "cron(0 9 * * ? *)"  # Primary: 9 AM daily

  additional_schedules = [
    {
      name                = "evening"
      schedule_expression = "cron(0 18 * * ? *)"  # 6 PM daily
      enabled             = true
    },
    {
      name                = "weekend-morning"
      schedule_expression = "cron(0 10 ? * SAT,SUN *)"  # 10 AM weekends
      enabled             = true
      overrides           = jsonencode({
        containerOverrides = [{
          name = "my-container"
          environment = [
            { name = "WEEKEND_MODE", value = "true" }
          ]
        }]
      })
    }
  ]
}
```

### Example with EC2 Launch Type and Placement Strategy

```hcl
module "ecs_scheduler" {
  source = "path/to/ecs_scheduler"

  # ... required variables ...

  launch_type = "EC2"

  placement_constraints = [
    {
      type       = "memberOf"
      expression = "attribute:ecs.availability-zone in [us-east-1a, us-east-1b]"
    }
  ]

  placement_strategy = [
    {
      type  = "spread"
      field = "attribute:ecs.availability-zone"
    },
    {
      type  = "binpack"
      field = "memory"
    }
  ]
}
```

### Example with Capacity Provider

```hcl
module "ecs_scheduler" {
  source = "path/to/ecs_scheduler"

  # ... required variables ...

  capacity_provider_name   = "my-capacity-provider"
  capacity_provider_weight = 100
  capacity_provider_base   = 1
}
```

## Security Best Practices

This module implements several security best practices:

### IAM Least Privilege

- **No broad permissions**: Removed `AmazonECS_FullAccess` in favor of specific permissions
- **Scoped resources**: All IAM actions are scoped to specific resources (cluster, task definitions)
- **Conditional permissions**: Uses IAM conditions to further restrict access
- **Permissions boundary support**: Optional permissions boundary for additional guardrails

### SQS Dead Letter Queue

- **Encrypted at rest**: Uses customer-managed KMS key
- **Restricted access**: Only EventBridge Scheduler can send messages
- **SSL enforced**: Denies non-SSL access to the queue
- **Configurable admin access**: Explicit list of principals for queue management

### Network Security

- **Private subnets**: Tasks run in specified private subnets
- **Security groups**: Configurable security group assignments
- **No public IP by default**: `assign_public_ip` defaults to false

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| aws | >= 5.0.0 |

## Inputs

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `cluster_name` | Name of the ECS cluster | `string` |
| `ecs_cluster_arn` | ARN of the ECS cluster | `string` |
| `task_name` | Name of the ECS task | `string` |
| `schedule_expression` | Cron or rate expression for the schedule | `string` |
| `trusted_compute_subnets` | List of subnet IDs for task networking | `list(string)` |
| `kms_key_arn` | ARN of KMS key for encryption | `string` |
| `resource_owner` | Owner (naming module) | `string` |
| `billing_entity` | Billing entity (naming module) | `string` |
| `billing_domain` | Billing domain (naming module) | `string` |
| `security_domain` | Security domain (naming module) | `string` |
| `aws_region_short_code` | Short region code (e.g., use1) | `string` |

### Optional Variables

| Name | Description | Default |
|------|-------------|---------|
| `enabled` | Enable/disable the schedule | `true` |
| `timezone` | Timezone for schedule expression | `"UTC"` |
| `launch_type` | ECS launch type (FARGATE/EC2/EXTERNAL) | `"FARGATE"` |
| `platform_version` | Fargate platform version | `"LATEST"` |
| `task_count` | Number of tasks to run | `1` |
| `maximum_retry_attempts` | Max retry attempts (0-185) | `5` |
| `maximum_event_age_in_seconds` | Max event age before discard | `86400` |
| `permissions_boundary_arn` | Permissions boundary for IAM role | `null` |
| `additional_tags` | Additional resource tags | `{}` |

See `variables.tf` for the complete list of configurable options.

## Outputs

| Name | Description |
|------|-------------|
| `schedule_group_arn` | ARN of the schedule group |
| `schedule_arns` | Map of schedule names to ARNs |
| `primary_schedule_arn` | ARN of the primary schedule |
| `dlq_arn` | ARN of the dead letter queue |
| `dlq_url` | URL of the dead letter queue |
| `scheduler_role_arn` | ARN of the scheduler IAM role |
| `task_definition_arn` | Task definition ARN used |

## Migration from Previous Version

If you're migrating from the previous version of this module, note the following changes:

### Breaking Changes

1. **Removed `AmazonECS_FullAccess`**: The overly permissive managed policy has been removed. The module now uses least-privilege inline policies.

2. **Security group input changed**: Use `security_group_ids` (list) instead of `security_group_id` (string). The old variable is deprecated but still works for backward compatibility.

3. **IAM role renamed**: The IAM role resource is now named `aws_iam_role.scheduler` instead of `aws_iam_role.ecs`.

### Migration Steps

```hcl
# Add these moved blocks to your configuration before upgrading

moved {
  from = module.ecs_scheduler.aws_iam_role.ecs
  to   = module.ecs_scheduler.aws_iam_role.scheduler
}

moved {
  from = module.ecs_scheduler.aws_iam_role_policy.ecs
  to   = module.ecs_scheduler.aws_iam_role_policy.scheduler
}

moved {
  from = module.ecs_scheduler.aws_sqs_queue.sqs_test_dlq
  to   = module.ecs_scheduler.aws_sqs_queue.dlq
}
```

## License

Copyright (c) [Your Company]. All rights reserved.
