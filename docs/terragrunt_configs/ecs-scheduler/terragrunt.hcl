# =============================================================================
# ECS Scheduler Module - Terragrunt Configuration
# =============================================================================
# This module creates EventBridge Scheduler schedules to run ECS tasks.
# Must be applied AFTER the ecs-task-role module.
# =============================================================================

terraform {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-scheduler.git?ref=v1.0"
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

dependency "ecs-cluster" {
  config_path = "../../../ecs-cluster"

  mock_outputs = {
    application_name   = "mock-app"
    cluster_arn        = "arn:aws:ecs:us-east-1:123456789012:cluster/mock-cluster"
    cluster_short_name = "mock-cluster"
    security_group_ids = ["sg-mock123"]
    private_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "kms-key-stack" {
  config_path = "../../../kms-key"

  mock_outputs = {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "task_role" {
  config_path = "../ecs-task-role"

  mock_outputs = {
    name               = "mock-task"
    short_name         = "mock"
    task_role_arn      = "arn:aws:iam::123456789012:role/mock-task-role"
    execution_role_arn = "arn:aws:iam::123456789012:role/mock-exec-role"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Optional: SNS topic for alerts
# dependency "sns-alerts" {
#   config_path = "../../../sns-alerts"
#   mock_outputs = {
#     topic_arn = "arn:aws:sns:us-east-1:123456789012:mock-alerts"
#   }
#   mock_outputs_allowed_terraform_commands = ["validate", "plan"]
# }

# -----------------------------------------------------------------------------
# Inputs
# -----------------------------------------------------------------------------

inputs = {
  # ---------------------------------------------------------------------------
  # Required Variables - Cluster & Task
  # ---------------------------------------------------------------------------
  
  cluster_name    = dependency.ecs-cluster.outputs.cluster_short_name
  ecs_cluster_arn = dependency.ecs-cluster.outputs.cluster_arn
  
  # Task naming (from IAM roles module outputs)
  task_name       = dependency.task_role.outputs.name
  short_task_name = dependency.task_role.outputs.short_name
  
  # ---------------------------------------------------------------------------
  # Required Variables - Schedule
  # ---------------------------------------------------------------------------
  
  # Cron expression: Every Wednesday at 11:00 UTC
  schedule_expression = "cron(0 11 ? * WED *)"
  
  # Timezone for schedule (default: UTC)
  timezone = "UTC"
  
  # Enable/disable the schedule
  enabled = true
  
  # ---------------------------------------------------------------------------
  # Required Variables - Network
  # ---------------------------------------------------------------------------
  
  # FIXED: Use security_group_ids (list) instead of security_group_id (string)
  security_group_ids = dependency.ecs-cluster.outputs.security_group_ids
  
  # NEW REQUIRED: Subnets for the ECS task
  trusted_compute_subnets = dependency.ecs-cluster.outputs.private_subnet_ids
  
  # ---------------------------------------------------------------------------
  # Required Variables - Security
  # ---------------------------------------------------------------------------
  
  kms_key_arn = dependency.kms-key-stack.outputs.kms_key_arn
  
  # ---------------------------------------------------------------------------
  # Required Variables - Naming Module
  # ---------------------------------------------------------------------------
  
  # NEW REQUIRED: Region short code
  aws_region_short_code = "use1"
  
  resource_owner  = "cloud"
  billing_domain  = "cloud"
  billing_entity  = "cloud"
  security_domain = "cloud"
  
  # ---------------------------------------------------------------------------
  # Recommended: IAM Role ARNs (for PassRole permission)
  # ---------------------------------------------------------------------------
  
  # NEW: Pass the task role ARN from the IAM roles module
  ecs_task_role_arn      = dependency.task_role.outputs.task_role_arn
  ecs_execution_role_arn = dependency.task_role.outputs.execution_role_arn
  
  # ---------------------------------------------------------------------------
  # Optional: Task Configuration
  # ---------------------------------------------------------------------------
  
  # Launch type (FARGATE, EC2, or EXTERNAL)
  launch_type = "FARGATE"
  
  # Platform version for Fargate (default: LATEST)
  platform_version = "LATEST"
  
  # Number of tasks to run (1-10)
  task_count = 1
  
  # Assign public IP (only for public subnets)
  assign_public_ip = false
  
  # ---------------------------------------------------------------------------
  # Optional: Retry Policy
  # ---------------------------------------------------------------------------
  
  # Maximum retry attempts (0-185, default: 5)
  maximum_retry_attempts = 5
  
  # Maximum event age before discard (60-86400 seconds, default: 24 hours)
  maximum_event_age_in_seconds = 86400
  
  # ---------------------------------------------------------------------------
  # Optional: DLQ Alerting (NEW FEATURE)
  # ---------------------------------------------------------------------------
  
  # Enable CloudWatch alarms for DLQ (default: true)
  enable_dlq_alarm = true
  
  # SNS topics to notify on alarm (uncomment and configure)
  # dlq_alarm_actions = [dependency.sns-alerts.outputs.topic_arn]
  # dlq_ok_actions    = [dependency.sns-alerts.outputs.topic_arn]
  
  # ---------------------------------------------------------------------------
  # Optional: Additional Schedules
  # ---------------------------------------------------------------------------
  
  # Uncomment to add more schedules for the same task
  # additional_schedules = [
  #   {
  #     name                = "evening"
  #     schedule_expression = "cron(0 18 ? * MON-FRI *)"
  #     enabled             = true
  #   },
  #   {
  #     name                = "weekend"
  #     schedule_expression = "cron(0 12 ? * SAT,SUN *)"
  #     enabled             = true
  #     overrides = jsonencode({
  #       containerOverrides = [{
  #         name = "main"
  #         environment = [
  #           { name = "WEEKEND_MODE", value = "true" }
  #         ]
  #       }]
  #     })
  #   }
  # ]
  
  # ---------------------------------------------------------------------------
  # Optional: Tags
  # ---------------------------------------------------------------------------
  
  additional_tags = {
    "managed-by" = "terragrunt"
    "schedule"   = "weekly-wednesday"
  }
}

# -----------------------------------------------------------------------------
# Include parent configuration
# -----------------------------------------------------------------------------

include {
  path = find_in_parent_folders()
}

