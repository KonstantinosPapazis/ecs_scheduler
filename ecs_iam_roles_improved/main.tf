################################################################################
# ECS IAM Roles Module - Main Resources
################################################################################

locals {
  aws_region     = data.aws_region.current.id
  aws_account_id = data.aws_caller_identity.current.account_id
  account_alias  = var.aws_account_aliases_v2[local.aws_account_id]

  # Computed short name
  short_name = coalesce(var.short_name, var.name)

  # IAM naming prefix
  iam_name_prefix = var.service_env == "" || var.service_env == var.env ? (
    "${var.aws_region_short_code}-${local.account_alias}-iam-${var.application_name}-${local.short_name}"
    ) : (
    "${var.aws_region_short_code}-${local.account_alias}-iam-${var.application_name}-${local.short_name}-${var.service_env}"
  )

  # Resolved service environment
  resolved_service_env = var.service_env == "" ? var.env : var.service_env

  # Billing entity fallback
  billing_entity = coalesce(var.billing_entity, var.resource_owner)

  # Standard tags
  tags = merge(
    var.tags,
    {
      "application-name"  = var.application_name
      "resource-contacts" = var.resource_contacts
      "resource-owner"    = var.resource_owner
      "billing-entity"    = local.billing_entity
      "billing-domain"    = var.billing_domain
      "security-domain"   = var.security_domain
      "deploy-tag"        = "cloud"
      "support-tag"       = "devops"
      "env"               = var.env
      "service-env"       = local.resolved_service_env
      "account-alias"     = local.account_alias
    }
  )
}

################################################################################
# ECS Task Role
# This role is assumed by your container to call AWS APIs (S3, DynamoDB, etc.)
################################################################################

resource "aws_iam_role" "task" {
  name                 = "${local.iam_name_prefix}-ecs-task-role"
  path                 = var.iam_role_path
  max_session_duration = var.task_role_max_session_duration
  description          = "ECS Task Role for ${var.application_name}/${var.name} - allows containers to call AWS APIs"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json

  force_detach_policies = true

  tags = merge(
    local.tags,
    {
      "Name" = "${local.iam_name_prefix}-ecs-task-role"
    }
  )
}

resource "aws_iam_policy" "task" {
  name        = "${local.iam_name_prefix}-ecs-task-policy"
  description = "ECS Task Policy for ${var.application_name}/${var.name}"
  policy      = data.aws_iam_policy_document.task_permissions.json

  tags = merge(
    local.tags,
    {
      "Name" = "${local.iam_name_prefix}-ecs-task-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task.arn
}

# Attach managed policies (user-provided)
resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each   = toset(var.task_role_managed_policies)
  role       = aws_iam_role.task.name
  policy_arn = each.value
}

# CloudWatch Agent Policy (optional)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_cloudwatch_agent ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

################################################################################
# ECS Task Execution Role
# This role is used by ECS to pull images, write logs, get secrets
################################################################################

resource "aws_iam_role" "execution" {
  name                 = "${local.iam_name_prefix}-task-exec-role"
  path                 = var.iam_role_path
  max_session_duration = 3600 # Execution role doesn't need long sessions
  description          = "ECS Task Execution Role for ${var.application_name}/${var.name} - allows ECS to pull images and write logs"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json

  force_detach_policies = true

  tags = merge(
    local.tags,
    {
      "Name" = "${local.iam_name_prefix}-task-exec-role"
    }
  )
}

resource "aws_iam_policy" "execution" {
  name        = "${local.iam_name_prefix}-ecs-task-exec-policy"
  description = "ECS Task Execution Policy for ${var.application_name}/${var.name}"
  policy      = data.aws_iam_policy_document.execution_permissions.json

  tags = merge(
    local.tags,
    {
      "Name" = "${local.iam_name_prefix}-ecs-task-exec-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution.arn
}

# Attach AWS managed ECS Task Execution Role Policy
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

