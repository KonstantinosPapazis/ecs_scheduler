#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where tasks will be scheduled"
  type        = string
}

variable "task_name" {
  description = "Name of the ECS task"
  type        = string
}

variable "schedule_expression" {
  description = "Schedule expression for the primary schedule (cron or rate expression)"
  type        = string
}

variable "trusted_compute_subnets" {
  description = "List of subnet IDs for the ECS task network configuration"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
}

#------------------------------------------------------------------------------
# Naming Module Variables
#------------------------------------------------------------------------------

variable "resource_owner" {
  description = "Owner of the resources (used by naming module)"
  type        = string
}

variable "billing_entity" {
  description = "Billing entity (used by naming module)"
  type        = string
}

variable "billing_domain" {
  description = "Billing domain (used by naming module)"
  type        = string
}

variable "security_domain" {
  description = "Security domain (used by naming module)"
  type        = string
}

variable "aws_region_short_code" {
  description = "Short code for AWS region (e.g., use1, usw2)"
  type        = string
}

#------------------------------------------------------------------------------
# Optional Variables - Schedule Configuration
#------------------------------------------------------------------------------

variable "short_task_name" {
  description = "Short name for the task (used in resource naming). Defaults to task_name if not provided"
  type        = string
  default     = null
}

variable "enabled" {
  description = "Whether the schedule is enabled"
  type        = bool
  default     = true
}

variable "timezone" {
  description = "Timezone for schedule expression evaluation"
  type        = string
  default     = "UTC"
}

variable "schedule_description" {
  description = "Description for the primary schedule"
  type        = string
  default     = null
}

variable "schedule_start_date" {
  description = "Date after which the schedule can begin invoking (ISO 8601 format)"
  type        = string
  default     = null
}

variable "schedule_end_date" {
  description = "Date before which the schedule can invoke (ISO 8601 format)"
  type        = string
  default     = null
}

variable "action_after_completion" {
  description = "Action after schedule completion: NONE or DELETE (useful for one-time schedules)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "DELETE"], var.action_after_completion)
    error_message = "action_after_completion must be either 'NONE' or 'DELETE'."
  }
}

variable "flexible_time_window_in_minutes" {
  description = "Maximum time window during which a schedule can be invoked (1-1440 minutes)"
  type        = number
  default     = null

  validation {
    condition     = var.flexible_time_window_in_minutes == null || (var.flexible_time_window_in_minutes >= 1 && var.flexible_time_window_in_minutes <= 1440)
    error_message = "flexible_time_window_in_minutes must be between 1 and 1440."
  }
}

variable "additional_schedules" {
  description = "Additional schedules to create for the same task"
  type = list(object({
    name_prefix                     = optional(string, "")
    name                            = string
    description                     = optional(string)
    schedule_expression             = string
    enabled                         = optional(bool)
    overrides                       = optional(string, "NONE")
    flexible_time_window_in_minutes = optional(number)
    start_date                      = optional(string)
    end_date                        = optional(string)
  }))
  default = []
}

#------------------------------------------------------------------------------
# Optional Variables - ECS Task Configuration
#------------------------------------------------------------------------------

variable "task_definition_arn" {
  description = "ARN of the ECS task definition. If not provided, it will be constructed using the naming module"
  type        = string
  default     = null
}

variable "overrides" {
  description = "JSON string of container overrides for the ECS task"
  type        = string
  default     = null
}

variable "launch_type" {
  description = "Launch type for ECS tasks: FARGATE, EC2, or EXTERNAL"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = var.launch_type == null || contains(["FARGATE", "EC2", "EXTERNAL"], var.launch_type)
    error_message = "launch_type must be FARGATE, EC2, or EXTERNAL."
  }
}

variable "platform_version" {
  description = "Platform version for Fargate tasks (e.g., LATEST, 1.4.0)"
  type        = string
  default     = "LATEST"
}

variable "task_count" {
  description = "Number of tasks to run (1-10)"
  type        = number
  default     = 1

  validation {
    condition     = var.task_count >= 1 && var.task_count <= 10
    error_message = "task_count must be between 1 and 10."
  }
}

variable "enable_ecs_managed_tags" {
  description = "Enable ECS managed tags for tasks"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging containers"
  type        = bool
  default     = false
}

variable "ecs_task_group" {
  description = "ECS task group name (max 255 characters)"
  type        = string
  default     = null

  validation {
    condition     = var.ecs_task_group == null || length(var.ecs_task_group) <= 255
    error_message = "ecs_task_group must be 255 characters or less."
  }
}

variable "reference_id" {
  description = "Reference ID for the task"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Optional Variables - Network Configuration
#------------------------------------------------------------------------------

variable "security_group_id" {
  description = "DEPRECATED: Use security_group_ids instead. Security group ID for the ECS task"
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs for the ECS task (1-5 groups)"
  type        = list(string)
  default     = null

  validation {
    condition     = var.security_group_ids == null || (length(var.security_group_ids) >= 1 && length(var.security_group_ids) <= 5)
    error_message = "security_group_ids must contain 1 to 5 security groups."
  }
}

variable "assign_public_ip" {
  description = "Assign public IP to Fargate tasks (only valid for Fargate launch type)"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Optional Variables - Capacity Provider
#------------------------------------------------------------------------------

variable "capacity_provider_name" {
  description = "Name of the capacity provider to use (mutually exclusive with launch_type)"
  type        = string
  default     = null
}

variable "capacity_provider_weight" {
  description = "Relative percentage of tasks using this capacity provider (0-1000)"
  type        = number
  default     = 1

  validation {
    condition     = var.capacity_provider_weight >= 0 && var.capacity_provider_weight <= 1000
    error_message = "capacity_provider_weight must be between 0 and 1000."
  }
}

variable "capacity_provider_base" {
  description = "Minimum number of tasks on this capacity provider (0-100000)"
  type        = number
  default     = 0

  validation {
    condition     = var.capacity_provider_base >= 0 && var.capacity_provider_base <= 100000
    error_message = "capacity_provider_base must be between 0 and 100000."
  }
}

#------------------------------------------------------------------------------
# Optional Variables - Placement (EC2 Launch Type)
#------------------------------------------------------------------------------

variable "placement_constraints" {
  description = "Placement constraints for EC2 launch type"
  type = list(object({
    type       = string
    expression = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for pc in var.placement_constraints : contains(["distinctInstance", "memberOf"], pc.type)
    ])
    error_message = "placement_constraints type must be 'distinctInstance' or 'memberOf'."
  }
}

variable "placement_strategy" {
  description = "Placement strategy for EC2 launch type"
  type = list(object({
    type  = string
    field = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for ps in var.placement_strategy : contains(["random", "spread", "binpack"], ps.type)
    ])
    error_message = "placement_strategy type must be 'random', 'spread', or 'binpack'."
  }
}

#------------------------------------------------------------------------------
# Optional Variables - Retry Policy
#------------------------------------------------------------------------------

variable "maximum_retry_attempts" {
  description = "Maximum number of retry attempts (0-185)"
  type        = number
  default     = 5

  validation {
    condition     = var.maximum_retry_attempts >= 0 && var.maximum_retry_attempts <= 185
    error_message = "maximum_retry_attempts must be between 0 and 185."
  }
}

variable "maximum_event_age_in_seconds" {
  description = "Maximum age of a request before it's discarded (60-86400 seconds)"
  type        = number
  default     = 86400

  validation {
    condition     = var.maximum_event_age_in_seconds >= 60 && var.maximum_event_age_in_seconds <= 86400
    error_message = "maximum_event_age_in_seconds must be between 60 and 86400."
  }
}

#------------------------------------------------------------------------------
# Optional Variables - Dead Letter Queue
#------------------------------------------------------------------------------

variable "dlq_message_retention_seconds" {
  description = "Message retention period for DLQ (60-1209600 seconds, default 14 days)"
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600."
  }
}

variable "dlq_visibility_timeout_seconds" {
  description = "Visibility timeout for DLQ messages (0-43200 seconds)"
  type        = number
  default     = 300

  validation {
    condition     = var.dlq_visibility_timeout_seconds >= 0 && var.dlq_visibility_timeout_seconds <= 43200
    error_message = "dlq_visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "dlq_receive_wait_time_seconds" {
  description = "Long polling wait time for DLQ (0-20 seconds)"
  type        = number
  default     = 20

  validation {
    condition     = var.dlq_receive_wait_time_seconds >= 0 && var.dlq_receive_wait_time_seconds <= 20
    error_message = "dlq_receive_wait_time_seconds must be between 0 and 20."
  }
}

variable "dlq_delay_seconds" {
  description = "Delay for DLQ messages (0-900 seconds)"
  type        = number
  default     = 0

  validation {
    condition     = var.dlq_delay_seconds >= 0 && var.dlq_delay_seconds <= 900
    error_message = "dlq_delay_seconds must be between 0 and 900."
  }
}

variable "dlq_max_message_size" {
  description = "Maximum message size for DLQ (1024-262144 bytes)"
  type        = number
  default     = 262144

  validation {
    condition     = var.dlq_max_message_size >= 1024 && var.dlq_max_message_size <= 262144
    error_message = "dlq_max_message_size must be between 1024 and 262144."
  }
}

variable "kms_data_key_reuse_period_seconds" {
  description = "Time in seconds to reuse KMS data key (60-86400)"
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

variable "dlq_admin_principals" {
  description = "List of IAM principal ARNs allowed to manage the DLQ"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Optional Variables - IAM Configuration
#------------------------------------------------------------------------------

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role. If not provided, it will be constructed using the naming module"
  type        = string
  default     = null
}

variable "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role (for pulling images, writing logs)"
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary to apply to the scheduler IAM role"
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration for the scheduler IAM role (3600-43200 seconds)"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200."
  }
}

variable "restrict_assume_role_to_schedule_group" {
  description = "Restrict the assume role policy to only allow the schedule group"
  type        = bool
  default     = false
}

variable "allow_stop_task" {
  description = "Allow the scheduler role to stop ECS tasks"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs permissions for the scheduler role"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Optional Variables - Tag Propagation
#------------------------------------------------------------------------------

variable "propagate_tags" {
  description = "Specifies whether to propagate tags from the task definition to the task"
  type        = string
  default     = "TASK_DEFINITION"

  validation {
    condition     = var.propagate_tags == null || var.propagate_tags == "TASK_DEFINITION"
    error_message = "propagate_tags must be 'TASK_DEFINITION' or null."
  }
}

#------------------------------------------------------------------------------
# Optional Variables - CloudWatch Alarms
#------------------------------------------------------------------------------

variable "enable_dlq_alarm" {
  description = "Enable CloudWatch alarm for DLQ messages (failed schedule invocations)"
  type        = bool
  default     = true
}

variable "dlq_alarm_threshold" {
  description = "Number of messages in DLQ to trigger alarm (0 = alert on any failure)"
  type        = number
  default     = 0
}

variable "dlq_alarm_evaluation_periods" {
  description = "Number of periods to evaluate for the alarm"
  type        = number
  default     = 1
}

variable "dlq_alarm_period_seconds" {
  description = "Period in seconds for the alarm metric evaluation"
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.dlq_alarm_period_seconds)
    error_message = "dlq_alarm_period_seconds must be 60, 300, 900, or 3600."
  }
}

variable "dlq_alarm_actions" {
  description = "List of ARNs to notify when DLQ alarm triggers (e.g., SNS topic ARNs)"
  type        = list(string)
  default     = []
}

variable "dlq_ok_actions" {
  description = "List of ARNs to notify when DLQ alarm returns to OK state"
  type        = list(string)
  default     = []
}

variable "dlq_alarm_treat_missing_data" {
  description = "How to treat missing data: notBreaching, breaching, ignore, or missing"
  type        = string
  default     = "notBreaching"

  validation {
    condition     = contains(["notBreaching", "breaching", "ignore", "missing"], var.dlq_alarm_treat_missing_data)
    error_message = "dlq_alarm_treat_missing_data must be notBreaching, breaching, ignore, or missing."
  }
}

#------------------------------------------------------------------------------
# Optional Variables - Tags
#------------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

