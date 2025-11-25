#------------------------------------------------------------------------------
# Resource Migrations
# 
# These moved blocks help migrate from the previous version of the module
# without destroying and recreating resources.
#
# IMPORTANT: After all existing module consumers have applied these migrations,
# these moved blocks can be safely removed in a future version.
#------------------------------------------------------------------------------

################################################################################
# Schedule Migration
################################################################################

# Migration from single schedule to for_each map (already in original module)
moved {
  from = aws_scheduler_schedule.ecs
  to   = aws_scheduler_schedule.ecs[""]
}

################################################################################
# IAM Role Migration
################################################################################

# Rename IAM role from .ecs to .scheduler for clarity
moved {
  from = aws_iam_role.ecs
  to   = aws_iam_role.scheduler
}

################################################################################
# IAM Policy Migration
################################################################################

# Rename IAM role policy from .ecs to .scheduler for clarity
moved {
  from = aws_iam_role_policy.ecs
  to   = aws_iam_role_policy.scheduler
}

################################################################################
# SQS Queue Migration
################################################################################

# Rename SQS DLQ from .sqs_test_dlq to .dlq for clarity
moved {
  from = aws_sqs_queue.sqs_test_dlq
  to   = aws_sqs_queue.dlq
}

# Note: If the original module had an SQS queue policy, add:
# moved {
#   from = aws_sqs_queue_policy.sqs_test_dlq
#   to   = aws_sqs_queue_policy.dlq
# }

################################################################################
# Removed Resources
################################################################################

# The following resource was REMOVED (not moved) as it violated least privilege:
# - aws_iam_role_policy_attachment.ra (attached AmazonECS_FullAccess)
#
# If you need to import this removal, use:
#   terraform state rm aws_iam_role_policy_attachment.ra
#
# Or add a removed block (Terraform 1.7+):
# removed {
#   from = aws_iam_role_policy_attachment.ra
#   lifecycle {
#     destroy = false
#   }
# }
