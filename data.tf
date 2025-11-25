#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# IAM Policy Document: Scheduler Assume Role Policy
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "AllowSchedulerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Optional: Add condition to restrict to specific schedules
    dynamic "condition" {
      for_each = var.restrict_assume_role_to_schedule_group ? [1] : []

      content {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [aws_scheduler_schedule_group.ecs.arn]
      }
    }
  }
}

#------------------------------------------------------------------------------
# IAM Policy Document: Scheduler Permissions (Least Privilege)
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_permissions" {
  # Permission to run ECS tasks
  statement {
    sid     = "AllowRunTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      "${local.task_definition_arn}",
      "${local.task_definition_arn}:*"
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  # Permission to tag ECS resources (scoped to cluster and tasks)
  statement {
    sid     = "AllowTagResource"
    effect  = "Allow"
    actions = ["ecs:TagResource"]
    resources = [
      var.ecs_cluster_arn,
      "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task/${var.cluster_name}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RunTask"]
    }
  }

  # Permission to stop tasks (optional, for graceful shutdown scenarios)
  dynamic "statement" {
    for_each = var.allow_stop_task ? [1] : []

    content {
      sid     = "AllowStopTask"
      effect  = "Allow"
      actions = ["ecs:StopTask"]
      resources = [
        "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:task/${var.cluster_name}/*"
      ]

      condition {
        test     = "ArnEquals"
        variable = "ecs:cluster"
        values   = [var.ecs_cluster_arn]
      }
    }
  }

  # Permission to send messages to DLQ
  statement {
    sid       = "AllowSendToDLQ"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  # Permission to use KMS for encryption/decryption
  statement {
    sid    = "AllowKMSOperations"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext"
    ]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "sqs.${local.aws_region}.amazonaws.com",
        "scheduler.${local.aws_region}.amazonaws.com"
      ]
    }
  }

  # Permission to pass role to ECS task
  statement {
    sid       = "AllowPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.ecs_task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Permission to pass execution role to ECS task (if specified)
  dynamic "statement" {
    for_each = var.ecs_execution_role_arn != null ? [1] : []

    content {
      sid       = "AllowPassExecutionRole"
      effect    = "Allow"
      actions   = ["iam:PassRole"]
      resources = [var.ecs_execution_role_arn]

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  # Permission to write CloudWatch logs (if enabled)
  dynamic "statement" {
    for_each = var.enable_cloudwatch_logs ? [1] : []

    content {
      sid    = "AllowCloudWatchLogs"
      effect = "Allow"
      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = [
        "arn:aws:logs:${local.aws_region}:${local.aws_account_id}:log-group:/aws/ecs/${var.cluster_name}/${local.short_task_name}:*"
      ]
    }
  }
}

#------------------------------------------------------------------------------
# IAM Policy Document: SQS DLQ Policy
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "sqs_dlq_policy" {
  # Allow EventBridge Scheduler to send messages
  statement {
    sid    = "AllowSchedulerSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${local.aws_region}:${local.aws_account_id}:schedule/${aws_scheduler_schedule_group.ecs.name}/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.aws_account_id]
    }
  }

  # Deny non-SSL access
  statement {
    sid    = "DenyNonSSLAccess"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.dlq.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow account principals to manage the queue (with conditions)
  dynamic "statement" {
    for_each = var.dlq_admin_principals

    content {
      sid    = "AllowAdminAccess${statement.key}"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      actions = [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:PurgeQueue"
      ]
      resources = [aws_sqs_queue.dlq.arn]
    }
  }
}

