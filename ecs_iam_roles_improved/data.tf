################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# Task Role - Assume Role Policy
################################################################################

data "aws_iam_policy_document" "task_assume_role" {
  # Standard ECS task assume role
  statement {
    sid     = "ECSTaskAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Additional assume role statements (optional)
  dynamic "statement" {
    for_each = var.additional_assume_role_policy

    content {
      sid     = lookup(statement.value, "sid", null)
      effect  = statement.value.effect
      actions = statement.value.actions

      dynamic "principals" {
        for_each = statement.value.principals

        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = coalesce(statement.value.conditions, [])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

################################################################################
# Task Role - Permissions Policy
################################################################################

data "aws_iam_policy_document" "task_permissions" {
  # ECS Exec support (for container debugging via SSM)
  dynamic "statement" {
    for_each = var.enable_ecs_exec ? [1] : []

    content {
      sid    = "ECSExecSSM"
      effect = "Allow"
      actions = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      resources = ["*"]
    }
  }

  # KMS Decrypt (scoped to specific key)
  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = concat([var.kms_key_arn], var.additional_kms_key_arns)
  }

  # S3 access (optional, scoped to specific bucket/prefix)
  dynamic "statement" {
    for_each = var.s3_bucket_arn != null ? [1] : []

    content {
      sid       = "S3ListBucket"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [var.s3_bucket_arn]

      # Optional: restrict to specific prefix
      dynamic "condition" {
        for_each = var.s3_prefix_restriction != null ? [1] : []

        content {
          test     = "StringLike"
          variable = "s3:prefix"
          values   = ["${var.application_name}/${var.name}/*"]
        }
      }
    }
  }

  dynamic "statement" {
    for_each = var.s3_bucket_arn != null ? [1] : []

    content {
      sid    = "S3ObjectAccess"
      effect = "Allow"
      actions = var.s3_write_access ? [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject"
        ] : [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
      resources = ["${var.s3_bucket_arn}/${var.application_name}/${var.name}/*"]
    }
  }

  # EFS access (optional, scoped to specific file systems)
  dynamic "statement" {
    for_each = length(var.efs_file_system_arns) > 0 ? [1] : []

    content {
      sid    = "EFSAccess"
      effect = "Allow"
      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      resources = var.efs_file_system_arns

      # Optional: restrict to specific access points
      dynamic "condition" {
        for_each = length(var.efs_access_point_arns) > 0 ? [1] : []

        content {
          test     = "StringEquals"
          variable = "elasticfilesystem:AccessPointArn"
          values   = var.efs_access_point_arns
        }
      }
    }
  }

  # Dynamic policy statements (user-provided)
  dynamic "statement" {
    for_each = var.dynamic_policy

    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = coalesce(lookup(statement.value, "condition", null), [])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

################################################################################
# Task Execution Role - Assume Role Policy
################################################################################

data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    sid     = "ECSTaskExecutionAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

################################################################################
# Task Execution Role - Permissions Policy
################################################################################

data "aws_iam_policy_document" "execution_permissions" {
  # SSM Parameter Store access (scoped to application)
  statement {
    sid    = "SSMGetParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${local.aws_region}:${local.aws_account_id}:parameter/${var.application_name}/*"
    ]
  }

  # Secrets Manager access (scoped to application)
  statement {
    sid    = "SecretsManagerGetSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:aws:secretsmanager:${local.aws_region}:${local.aws_account_id}:secret:${var.application_name}/*"
    ]
  }

  # Secrets Manager with tag-based access (for cross-application secrets)
  dynamic "statement" {
    for_each = var.enable_tagged_secrets_access ? [1] : []

    content {
      sid    = "SecretsManagerTagBased"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/security-domain"
        values   = [var.security_domain]
      }
    }
  }

  # KMS Decrypt for secrets/parameters
  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = concat([var.kms_key_arn], var.additional_kms_key_arns)
  }

  # S3 access for task artifacts (optional)
  dynamic "statement" {
    for_each = var.s3_bucket_arn != null ? [1] : []

    content {
      sid       = "S3ListBucket"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [var.s3_bucket_arn]
    }
  }

  dynamic "statement" {
    for_each = var.s3_bucket_arn != null ? [1] : []

    content {
      sid    = "S3GetObject"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
      resources = ["${var.s3_bucket_arn}/${var.application_name}/${var.name}/*"]
    }
  }

  # EFS access (optional)
  dynamic "statement" {
    for_each = length(var.efs_file_system_arns) > 0 ? [1] : []

    content {
      sid    = "EFSAccess"
      effect = "Allow"
      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ]
      resources = var.efs_file_system_arns
    }
  }
}

