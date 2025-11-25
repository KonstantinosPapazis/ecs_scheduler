################################################################################
# Task Role Outputs
################################################################################

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.task.name
}

output "task_role_id" {
  description = "ID of the ECS task role"
  value       = aws_iam_role.task.id
}

output "task_role_unique_id" {
  description = "Unique ID of the ECS task role"
  value       = aws_iam_role.task.unique_id
}

output "task_policy_arn" {
  description = "ARN of the ECS task policy"
  value       = aws_iam_policy.task.arn
}

################################################################################
# Task Execution Role Outputs
################################################################################

output "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.execution.name
}

output "execution_role_id" {
  description = "ID of the ECS task execution role"
  value       = aws_iam_role.execution.id
}

output "execution_role_unique_id" {
  description = "Unique ID of the ECS task execution role"
  value       = aws_iam_role.execution.unique_id
}

output "execution_policy_arn" {
  description = "ARN of the ECS task execution policy"
  value       = aws_iam_policy.execution.arn
}

################################################################################
# Name Outputs (for dependencies)
################################################################################

output "name" {
  description = "Name of the ECS task/service"
  value       = var.name
}

output "short_name" {
  description = "Short name of the ECS task/service"
  value       = local.short_name
}

output "application_name" {
  description = "Application name"
  value       = var.application_name
}

output "iam_name_prefix" {
  description = "IAM naming prefix used for resources"
  value       = local.iam_name_prefix
}

################################################################################
# Computed Outputs (for debugging/reference)
################################################################################

output "tags" {
  description = "Tags applied to all resources"
  value       = local.tags
}

