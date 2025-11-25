# =============================================================================
# ECS IAM Roles Module - Terragrunt Configuration
# =============================================================================
# This module creates the IAM Task Role and Task Execution Role for ECS tasks.
# Must be applied BEFORE the ecs-scheduler module.
# =============================================================================

terraform {
  source = "git::ssh://git@bitbucket.jota.com:8998/terraform-ecs-iam-roles.git?ref=v1.0"
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

dependency "ecs-cluster" {
  config_path = "../../../ecs-cluster"

  # Mock outputs for `terragrunt validate` when dependency hasn't been applied
  mock_outputs = {
    application_name = "mock-app"
    cluster_arn      = "arn:aws:ecs:us-east-1:123456789012:cluster/mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "kms-key" {
  config_path = "../../../kms-key"

  mock_outputs = {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# -----------------------------------------------------------------------------
# Inputs
# -----------------------------------------------------------------------------

inputs = {
  # ---------------------------------------------------------------------------
  # Required Variables
  # ---------------------------------------------------------------------------
  
  name             = "test-mota-ecs"
  short_name       = "test-meta"
  application_name = dependency.ecs-cluster.outputs.application_name
  
  # KMS Key (RENAMED from kms_key_id to kms_key_arn)
  kms_key_arn = dependency.kms-key.outputs.kms_key_arn
  
  # NEW REQUIRED: Environment
  env = "prod"  # Change per environment: dev, staging, prod
  
  # NEW REQUIRED: Region short code
  aws_region_short_code = "use1"  # us-east-1 = use1, us-west-2 = usw2, eu-west-1 = euw1
  
  # NEW REQUIRED: Account aliases map
  # This should come from a common locals file or root terragrunt.hcl
  aws_account_aliases_v2 = {
    "123456789012" = "prod"
    "234567890123" = "staging"
    "345678901234" = "dev"
  }
  
  # Ownership & Billing
  resource_owner = "cloud"
  billing_entity = "cloud"
  billing_domain = "cloud"
  security_domain = "cloud"
  
  # ---------------------------------------------------------------------------
  # Optional: S3 Access (uncomment if needed)
  # ---------------------------------------------------------------------------
  
  # s3_bucket_arn   = dependency.s3-bucket.outputs.bucket_arn
  # s3_write_access = true  # Set to false for read-only access
  
  # ---------------------------------------------------------------------------
  # Optional: EFS Access (uncomment if needed)
  # ---------------------------------------------------------------------------
  
  # efs_file_system_arns  = [dependency.efs.outputs.file_system_arn]
  # efs_access_point_arns = [dependency.efs.outputs.access_point_arn]
  
  # ---------------------------------------------------------------------------
  # Optional: Additional KMS Keys (uncomment if needed)
  # ---------------------------------------------------------------------------
  
  # additional_kms_key_arns = [
  #   dependency.other-kms-key.outputs.kms_key_arn
  # ]
  
  # ---------------------------------------------------------------------------
  # Optional: CloudWatch Agent (default: disabled)
  # ---------------------------------------------------------------------------
  
  enable_cloudwatch_agent = false
  
  # ---------------------------------------------------------------------------
  # Optional: ECS Exec for debugging (default: enabled)
  # ---------------------------------------------------------------------------
  
  enable_ecs_exec = true
  
  # ---------------------------------------------------------------------------
  # Optional: Managed Policies (RENAMED from managed_policies)
  # ---------------------------------------------------------------------------
  
  # task_role_managed_policies = [
  #   "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  # ]
  
  # ---------------------------------------------------------------------------
  # Dynamic Policy - Custom IAM statements
  # ---------------------------------------------------------------------------
  
  dynamic_policy = [
    {
      sid    = "AllowEC2Describe"
      effect = "Allow"
      actions = [
        "ec2:DescribeRegions",
        "ec2:DescribeInstances"
      ]
      resources = ["*"]
    },
    {
      sid    = "AllowS3ListBuckets"
      effect = "Allow"
      actions = [
        "s3:ListAllMyBuckets"
      ]
      resources = ["*"]
    },
    {
      sid    = "AllowCloudWatchLogs"
      effect = "Allow"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = ["arn:aws:logs:*:*:*"]
    }
  ]
  
  # ---------------------------------------------------------------------------
  # Tags
  # ---------------------------------------------------------------------------
  
  tags = {
    "billing-domain"  = "cloud"
    "security-domain" = "cloud"
    "resource-owner"  = "cloud"
    "billing-entity"  = "cloud"
    "managed-by"      = "terragrunt"
  }
}

# -----------------------------------------------------------------------------
# Include parent configuration
# -----------------------------------------------------------------------------

include {
  path = find_in_parent_folders()
}

