#------------------------------------------------------------------------------
# Schedule Outputs
#------------------------------------------------------------------------------

output "schedule_group_arn" {
  description = "ARN of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.ecs.arn
}

output "schedule_group_name" {
  description = "Name of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.ecs.name
}

output "schedule_arns" {
  description = "Map of schedule names to their ARNs"
  value       = { for k, v in aws_scheduler_schedule.ecs : k => v.arn }
}

output "schedule_names" {
  description = "Map of schedule keys to their names"
  value       = { for k, v in aws_scheduler_schedule.ecs : k => v.name }
}

output "primary_schedule_arn" {
  description = "ARN of the primary schedule (empty string key)"
  value       = try(aws_scheduler_schedule.ecs[""].arn, null)
}

output "primary_schedule_name" {
  description = "Name of the primary schedule"
  value       = try(aws_scheduler_schedule.ecs[""].name, null)
}

#------------------------------------------------------------------------------
# Dead Letter Queue Outputs
#------------------------------------------------------------------------------

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  description = "Name of the dead letter queue"
  value       = aws_sqs_queue.dlq.name
}

#------------------------------------------------------------------------------
# CloudWatch Alarm Outputs
#------------------------------------------------------------------------------

output "dlq_messages_alarm_arn" {
  description = "ARN of the CloudWatch alarm for DLQ messages"
  value       = try(aws_cloudwatch_metric_alarm.dlq_messages_visible[0].arn, null)
}

output "dlq_messages_alarm_name" {
  description = "Name of the CloudWatch alarm for DLQ messages"
  value       = try(aws_cloudwatch_metric_alarm.dlq_messages_visible[0].alarm_name, null)
}

output "dlq_age_alarm_arn" {
  description = "ARN of the CloudWatch alarm for DLQ message age"
  value       = try(aws_cloudwatch_metric_alarm.dlq_oldest_message[0].arn, null)
}

output "dlq_age_alarm_name" {
  description = "Name of the CloudWatch alarm for DLQ message age"
  value       = try(aws_cloudwatch_metric_alarm.dlq_oldest_message[0].alarm_name, null)
}

#------------------------------------------------------------------------------
# IAM Role Outputs
#------------------------------------------------------------------------------

output "scheduler_role_arn" {
  description = "ARN of the EventBridge Scheduler IAM role"
  value       = aws_iam_role.scheduler.arn
}

output "scheduler_role_name" {
  description = "Name of the EventBridge Scheduler IAM role"
  value       = aws_iam_role.scheduler.name
}

output "scheduler_role_unique_id" {
  description = "Unique ID of the EventBridge Scheduler IAM role"
  value       = aws_iam_role.scheduler.unique_id
}

#------------------------------------------------------------------------------
# Computed Values
#------------------------------------------------------------------------------

output "task_definition_arn" {
  description = "Task definition ARN used by the schedules"
  value       = local.task_definition_arn
}

output "short_task_name" {
  description = "Short task name used in resource naming"
  value       = local.short_task_name
}

#------------------------------------------------------------------------------
# All Resources Output (for debugging/integration)
#------------------------------------------------------------------------------

output "all_schedule_details" {
  description = "Detailed information about all schedules"
  value = {
    for k, v in aws_scheduler_schedule.ecs : k => {
      arn                 = v.arn
      name                = v.name
      state               = v.state
      schedule_expression = v.schedule_expression
      timezone            = v.schedule_expression_timezone
      group_name          = v.group_name
    }
  }
}

