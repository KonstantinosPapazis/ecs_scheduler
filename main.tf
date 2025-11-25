################################################################################
# ECS Scheduler Module - Main Resources
################################################################################

locals {
  aws_region      = data.aws_region.current.id
  aws_account_id  = data.aws_caller_identity.current.account_id
  short_task_name = coalesce(var.short_task_name, var.task_name)

  # Handle backward compatibility for security_group_id -> security_group_ids
  security_group_ids = coalesce(
    var.security_group_ids,
    var.security_group_id != null ? [var.security_group_id] : null
  )

  # Merge default schedule with additional schedules
  schedules = concat([{
    name                            = ""
    name_prefix                     = ""
    description                     = var.schedule_description
    schedule_expression             = var.schedule_expression
    enabled                         = var.enabled
    overrides                       = var.overrides
    flexible_time_window_in_minutes = var.flexible_time_window_in_minutes
    start_date                      = var.schedule_start_date
    end_date                        = var.schedule_end_date
  }], var.additional_schedules)

  # Build task definition ARN
  task_definition_arn = coalesce(
    var.task_definition_arn,
    "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task-definition/${module.naming.ecs_task_def}"
  )

  # Build ECS task role ARN for PassRole permission
  ecs_task_role_arn = coalesce(
    var.ecs_task_role_arn,
    "arn:aws:iam::${local.aws_account_id}:role/${module.naming.iam_name_prefix}*"
  )
}

################################################################################
# Naming Module
################################################################################

module "naming" {
  source          = "git::ssh://git@bitbucket.jota.com:8998/terraform-naming.git?ref=v6"
  resource_owner  = var.resource_owner
  primary_name    = var.cluster_name
  secondary_name  = local.short_task_name
  billing_entity  = var.billing_entity
  billing_domain  = var.billing_domain
  security_domain = var.security_domain
}

################################################################################
# EventBridge Scheduler Schedule Group
################################################################################

resource "aws_scheduler_schedule_group" "ecs" {
  name = module.naming.cloudwatch_schedule

  tags = merge(
    module.naming.tags,
    {
      "Name" = module.naming.cloudwatch_schedule
    },
    var.additional_tags
  )
}

################################################################################
# EventBridge Scheduler Schedules
################################################################################

resource "aws_scheduler_schedule" "ecs" {
  for_each = { for schedule in local.schedules : schedule.name => schedule }

  name        = "${module.naming.cloudwatch_log_group_name_prefix}-${local.short_task_name}${each.value.name_prefix}${each.value.name}-cw-schedule"
  group_name  = aws_scheduler_schedule_group.ecs.name
  description = coalesce(each.value.description, "ECS scheduled task for ${local.short_task_name}${each.value.name_prefix}${each.value.name}")

  state = (coalesce(each.value.enabled, var.enabled)) ? "ENABLED" : "DISABLED"

  # Schedule timing
  schedule_expression          = each.value.schedule_expression
  schedule_expression_timezone = var.timezone

  # Optional start/end dates for time-bounded schedules
  start_date = each.value.start_date
  end_date   = each.value.end_date

  # Action after completion (useful for one-time schedules)
  action_after_completion = var.action_after_completion

  # Flexible time window configuration
  flexible_time_window {
    mode                      = each.value.flexible_time_window_in_minutes != null ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = each.value.flexible_time_window_in_minutes
  }

  # KMS encryption
  kms_key_arn = var.kms_key_arn

  # Target configuration
  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    # Enhanced retry policy with configurable settings
    retry_policy {
      maximum_retry_attempts       = var.maximum_retry_attempts
      maximum_event_age_in_seconds = var.maximum_event_age_in_seconds
    }

    # Dead letter queue for failed invocations
    dead_letter_config {
      arn = aws_sqs_queue.dlq.arn
    }

    # Task overrides (container overrides, environment variables, etc.)
    input = each.value.overrides == "NONE" ? var.overrides : each.value.overrides

    # ECS-specific parameters
    ecs_parameters {
      task_definition_arn = local.task_definition_arn

      # Task count (1-10)
      task_count = var.task_count

      # Launch configuration
      launch_type      = var.launch_type
      platform_version = var.launch_type == "FARGATE" ? var.platform_version : null

      # Tagging configuration
      enable_ecs_managed_tags = var.enable_ecs_managed_tags
      propagate_tags          = var.propagate_tags

      # Optional task group for tracking
      group = var.ecs_task_group

      # Network configuration (required for awsvpc network mode)
      network_configuration {
        subnets          = var.trusted_compute_subnets
        security_groups  = local.security_group_ids
        assign_public_ip = var.assign_public_ip
      }

      # Capacity provider strategy (alternative to launch_type)
      dynamic "capacity_provider_strategy" {
        for_each = var.capacity_provider_name != null ? [true] : []

        content {
          capacity_provider = var.capacity_provider_name
          weight            = var.capacity_provider_weight
          base              = var.capacity_provider_base
        }
      }

      # Placement constraints for EC2 launch type
      dynamic "placement_constraints" {
        for_each = var.placement_constraints

        content {
          type       = placement_constraints.value.type
          expression = placement_constraints.value.expression
        }
      }

      # Placement strategy for EC2 launch type
      dynamic "placement_strategy" {
        for_each = var.placement_strategy

        content {
          type  = placement_strategy.value.type
          field = placement_strategy.value.field
        }
      }

      # Additional tags for tasks
      tags = merge(
        module.naming.tags,
        {
          "ScheduleName" = each.key
        },
        var.additional_tags
      )
    }
  }
}

################################################################################
# SQS Dead Letter Queue
################################################################################

resource "aws_sqs_queue" "dlq" {
  name = module.naming.sqs_queue_name

  # Encryption
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  # Message configuration
  message_retention_seconds  = var.dlq_message_retention_seconds
  visibility_timeout_seconds = var.dlq_visibility_timeout_seconds
  receive_wait_time_seconds  = var.dlq_receive_wait_time_seconds
  delay_seconds              = var.dlq_delay_seconds
  max_message_size           = var.dlq_max_message_size

  tags = merge(
    module.naming.tags,
    {
      "Name"    = module.naming.sqs_queue_name
      "Purpose" = "ECS Scheduler Dead Letter Queue"
    },
    var.additional_tags
  )
}

# SQS Queue Policy - Restrict access to EventBridge Scheduler only
resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.sqs_dlq_policy.json
}

################################################################################
# IAM Role for EventBridge Scheduler
################################################################################

resource "aws_iam_role" "scheduler" {
  name        = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-role"
  description = "IAM role for EventBridge Scheduler to run ECS tasks for ${local.short_task_name}"

  assume_role_policy    = data.aws_iam_policy_document.scheduler_assume_role.json
  permissions_boundary  = var.permissions_boundary_arn
  max_session_duration  = var.max_session_duration
  force_detach_policies = true

  tags = merge(
    module.naming.tags,
    {
      "Name" = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-role"
    },
    var.additional_tags
  )
}

################################################################################
# IAM Role Policy for EventBridge Scheduler (Least Privilege)
################################################################################

resource "aws_iam_role_policy" "scheduler" {
  name   = "${module.naming.iam_name_prefix}-${var.aws_region_short_code}-${local.short_task_name}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_permissions.json
}

################################################################################
# CloudWatch Alarms for DLQ Monitoring
################################################################################

# Alarm when messages appear in the DLQ (indicates failed schedule invocations)
resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  count = var.enable_dlq_alarm ? 1 : 0

  alarm_name          = "${module.naming.cloudwatch_schedule}-dlq-messages-alarm"
  alarm_description   = "Alert when ECS scheduled task invocations fail and messages appear in DLQ for ${local.short_task_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.dlq_alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.dlq_alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.dlq_alarm_threshold
  treat_missing_data  = var.dlq_alarm_treat_missing_data

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = var.dlq_alarm_actions
  ok_actions    = var.dlq_ok_actions

  tags = merge(
    module.naming.tags,
    {
      "Name"    = "${module.naming.cloudwatch_schedule}-dlq-messages-alarm"
      "Purpose" = "Monitor failed ECS scheduled task invocations"
    },
    var.additional_tags
  )
}

# Alarm for DLQ age (messages sitting too long without being processed)
resource "aws_cloudwatch_metric_alarm" "dlq_oldest_message" {
  count = var.enable_dlq_alarm ? 1 : 0

  alarm_name          = "${module.naming.cloudwatch_schedule}-dlq-age-alarm"
  alarm_description   = "Alert when messages in DLQ are older than 1 hour (not being processed) for ${local.short_task_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.dlq_alarm_evaluation_periods
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = var.dlq_alarm_period_seconds
  statistic           = "Maximum"
  threshold           = 3600 # 1 hour in seconds
  treat_missing_data  = var.dlq_alarm_treat_missing_data

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = var.dlq_alarm_actions
  ok_actions    = var.dlq_ok_actions

  tags = merge(
    module.naming.tags,
    {
      "Name"    = "${module.naming.cloudwatch_schedule}-dlq-age-alarm"
      "Purpose" = "Monitor unprocessed messages in DLQ"
    },
    var.additional_tags
  )
}
