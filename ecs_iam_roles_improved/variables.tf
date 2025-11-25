################################################################################
# Required Variables
################################################################################

variable "name" {
  description = "Name of the ECS task/service"
  type        = string
}

variable "application_name" {
  description = "Name of the application (used for resource naming and access scoping)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption/decryption"
  type        = string
}

variable "resource_owner" {
  description = "Owner of the resources (team or individual)"
  type        = string
}

variable "env" {
  description = "Environment (e.g., dev, staging, prod)"
  type        = string
}

variable "aws_account_aliases_v2" {
  description = "Map of AWS account IDs to their aliases"
  type        = map(string)
}

variable "aws_region_short_code" {
  description = "Short code for AWS region (e.g., use1, usw2, euw1)"
  type        = string
}

################################################################################
# Optional Variables - Naming
################################################################################

variable "short_name" {
  description = "Short name for the task (used in resource naming). Defaults to name if not provided"
  type        = string
  default     = null
}

variable "service_env" {
  description = "Service environment (if different from env)"
  type        = string
  default     = ""
}

################################################################################
# Optional Variables - Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "billing_entity" {
  description = "Billing entity for cost allocation. Defaults to resource_owner if not provided"
  type        = string
  default     = null
}

variable "billing_domain" {
  description = "Billing domain for cost allocation"
  type        = string
  default     = "engineering"
}

variable "security_domain" {
  description = "Security domain for access control"
  type        = string
  default     = "internal"
}

variable "resource_contacts" {
  description = "Contact email for resources"
  type        = string
  default     = "cloud@jota.com"
}

################################################################################
# Optional Variables - IAM Configuration
################################################################################

variable "iam_role_path" {
  description = "Path for IAM roles"
  type        = string
  default     = "/"
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary to apply to IAM roles"
  type        = string
  default     = null
}

variable "task_role_max_session_duration" {
  description = "Maximum session duration for the task role (3600-43200 seconds)"
  type        = number
  default     = 14400

  validation {
    condition     = var.task_role_max_session_duration >= 3600 && var.task_role_max_session_duration <= 43200
    error_message = "task_role_max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "task_role_managed_policies" {
  description = "List of managed policy ARNs to attach to the task role"
  type        = list(string)
  default     = []
}

################################################################################
# Optional Variables - Task Role Permissions
################################################################################

variable "enable_ecs_exec" {
  description = "Enable ECS Exec for container debugging via SSM"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_agent" {
  description = "Attach CloudWatch Agent policy to task role"
  type        = bool
  default     = false
}

variable "additional_kms_key_arns" {
  description = "Additional KMS key ARNs for encryption/decryption"
  type        = list(string)
  default     = []
}

################################################################################
# Optional Variables - S3 Access
################################################################################

variable "s3_bucket_arn" {
  description = "ARN of S3 bucket for task data access"
  type        = string
  default     = null
}

variable "s3_write_access" {
  description = "Allow write access to S3 (PutObject, DeleteObject). If false, only read access is granted"
  type        = bool
  default     = true
}

variable "s3_prefix_restriction" {
  description = "Enable prefix restriction for S3 ListBucket operations"
  type        = bool
  default     = true
}

################################################################################
# Optional Variables - EFS Access
################################################################################

variable "efs_file_system_arns" {
  description = "List of EFS file system ARNs for mount access"
  type        = list(string)
  default     = []
}

variable "efs_access_point_arns" {
  description = "List of EFS access point ARNs (optional, for additional restriction)"
  type        = list(string)
  default     = []
}

################################################################################
# Optional Variables - Secrets Manager
################################################################################

variable "enable_tagged_secrets_access" {
  description = "Enable access to secrets with matching security-domain tag"
  type        = bool
  default     = true
}

################################################################################
# Optional Variables - Dynamic Policy
################################################################################

variable "dynamic_policy" {
  description = "Additional IAM policy statements for the task role"
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })))
  }))
  default = []
}

variable "additional_assume_role_policy" {
  description = "Additional assume role policy statements for the task role"
  type = list(object({
    sid     = optional(string)
    effect  = string
    actions = list(string)
    principals = list(object({
      type        = string
      identifiers = list(string)
    }))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })))
  }))
  default = []
}

