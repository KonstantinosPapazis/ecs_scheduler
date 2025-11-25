# ECS IAM Roles Module

This Terraform module creates IAM roles and policies for ECS tasks following AWS security best practices.

## What This Module Creates

### 1. ECS Task Role
- **Purpose:** Allows your container to call AWS APIs (S3, DynamoDB, SQS, etc.)
- **Assumed by:** `ecs-tasks.amazonaws.com`
- **Configurable permissions:** S3, EFS, KMS, ECS Exec, custom policies

### 2. ECS Task Execution Role
- **Purpose:** Allows ECS to pull images, write logs, and fetch secrets
- **Assumed by:** `ecs-tasks.amazonaws.com`
- **Permissions:** ECR, CloudWatch Logs, Secrets Manager, SSM Parameter Store

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ECS TASK IAM ROLES                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────┐   ┌─────────────────────────────┐  │
│  │      ECS TASK ROLE              │   │   ECS TASK EXECUTION ROLE   │  │
│  │                                 │   │                             │  │
│  │  Used BY: Your container        │   │  Used BY: ECS Agent         │  │
│  │                                 │   │                             │  │
│  │  Permissions:                   │   │  Permissions:               │  │
│  │  • S3 access (scoped)          │   │  • ECR pull                 │  │
│  │  • KMS decrypt                 │   │  • CloudWatch Logs write    │  │
│  │  • EFS mount (scoped)          │   │  • Secrets Manager read     │  │
│  │  • ECS Exec (SSM)              │   │  • SSM Parameter read       │  │
│  │  • Custom policies             │   │  • KMS decrypt              │  │
│  └─────────────────────────────────┘   └─────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Usage

### Basic Example

```hcl
module "ecs_iam_roles" {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-iam-roles.git?ref=v1.0"

  name             = "my-service"
  application_name = "my-app"
  kms_key_arn      = aws_kms_key.main.arn
  resource_owner   = "platform-team"
  env              = "prod"
  
  aws_account_aliases_v2 = {
    "123456789012" = "prod"
  }
  aws_region_short_code = "use1"
}
```

### With S3 Access

```hcl
module "ecs_iam_roles" {
  source = "..."

  # ... required variables ...

  s3_bucket_arn   = aws_s3_bucket.data.arn
  s3_write_access = true  # Allow PutObject, DeleteObject
}
```

### With EFS Access

```hcl
module "ecs_iam_roles" {
  source = "..."

  # ... required variables ...

  efs_file_system_arns  = [aws_efs_file_system.main.arn]
  efs_access_point_arns = [aws_efs_access_point.app.arn]
}
```

### With Custom Policies

```hcl
module "ecs_iam_roles" {
  source = "..."

  # ... required variables ...

  dynamic_policy = [
    {
      sid       = "AllowDynamoDB"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
      resources = [aws_dynamodb_table.main.arn]
    },
    {
      sid       = "AllowSQS"
      effect    = "Allow"
      actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
      resources = [aws_sqs_queue.main.arn]
    }
  ]
}
```

## Security Best Practices

This module implements several security best practices:

### 1. Least Privilege
- All permissions are scoped to specific resources
- No `Resource: "*"` except for ECS Exec (SSM) which requires it
- S3 access is scoped to `{bucket}/{application}/{name}/*`

### 2. Conditional Access
- EFS access can be restricted to specific access points
- Secrets Manager tag-based access for cross-application secrets
- S3 prefix restrictions for ListBucket

### 3. Optional Features
- ECS Exec is opt-in (enabled by default for debugging)
- CloudWatch Agent policy is opt-in (disabled by default)
- All S3/EFS permissions require explicit configuration

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| `name` | Name of the ECS task/service | `string` |
| `application_name` | Name of the application | `string` |
| `kms_key_arn` | ARN of the KMS key | `string` |
| `resource_owner` | Owner of the resources | `string` |
| `env` | Environment | `string` |
| `aws_account_aliases_v2` | Map of account IDs to aliases | `map(string)` |
| `aws_region_short_code` | Short region code | `string` |

### Optional

| Name | Default | Description |
|------|---------|-------------|
| `short_name` | `null` | Short name for resource naming |
| `enable_ecs_exec` | `true` | Enable ECS Exec for debugging |
| `enable_cloudwatch_agent` | `false` | Attach CloudWatch Agent policy |
| `s3_bucket_arn` | `null` | S3 bucket for data access |
| `s3_write_access` | `true` | Allow S3 write operations |
| `efs_file_system_arns` | `[]` | EFS file systems to mount |
| `dynamic_policy` | `[]` | Additional IAM policy statements |

## Outputs

| Name | Description |
|------|-------------|
| `task_role_arn` | ARN of the ECS task role |
| `task_role_name` | Name of the ECS task role |
| `execution_role_arn` | ARN of the ECS task execution role |
| `execution_role_name` | Name of the ECS task execution role |
| `name` | Name of the task (for dependencies) |
| `short_name` | Short name of the task |

## Integration with ECS Scheduler Module

```hcl
# Step 1: Create IAM roles
module "ecs_iam_roles" {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-iam-roles.git?ref=v1.0"
  # ... configuration ...
}

# Step 2: Create ECS task definition (uses both roles)
resource "aws_ecs_task_definition" "main" {
  family             = module.ecs_iam_roles.name
  task_role_arn      = module.ecs_iam_roles.task_role_arn
  execution_role_arn = module.ecs_iam_roles.execution_role_arn
  # ... rest of configuration ...
}

# Step 3: Create scheduler (needs task role ARN for PassRole)
module "ecs_scheduler" {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-scheduler.git?ref=v1.0"
  
  task_name         = module.ecs_iam_roles.name
  short_task_name   = module.ecs_iam_roles.short_name
  ecs_task_role_arn = module.ecs_iam_roles.task_role_arn
  # ... rest of configuration ...
}
```

## Changes from Original Module

### Bugs Fixed
- Removed duplicate ECS statement
- Fixed typo: `additonal_kms_key_ids` → `additional_kms_key_arns`
- Fixed typo: `conditions.value` → `condition.value`

### Security Improvements
- EFS permissions scoped to specific file systems (was `*`)
- S3 actions explicit instead of wildcard `s3:*Object*`
- CloudWatch Agent policy now optional
- Added permissions boundary support

### New Features
- Comprehensive outputs (role ARNs, names, etc.)
- Variable validations
- Configurable S3 write access
- EFS access point restrictions
- Full documentation

## License

Copyright (c) [Your Company]. All rights reserved.

