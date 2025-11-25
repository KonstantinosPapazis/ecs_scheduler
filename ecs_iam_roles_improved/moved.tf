################################################################################
# Resource Migrations
#
# These moved blocks help migrate from the previous version of the module
# without destroying and recreating resources.
#
# IMPORTANT: After all existing module consumers have applied these migrations,
# these moved blocks can be safely removed in a future version.
################################################################################

################################################################################
# Task Role Migrations
################################################################################

moved {
  from = aws_iam_role.ecs_task_role
  to   = aws_iam_role.task
}

moved {
  from = aws_iam_policy.task_role
  to   = aws_iam_policy.task
}

moved {
  from = aws_iam_role_policy_attachment.task_role
  to   = aws_iam_role_policy_attachment.task
}

moved {
  from = aws_iam_role_policy_attachment.managed_role
  to   = aws_iam_role_policy_attachment.task_managed
}

################################################################################
# Task Execution Role Migrations
################################################################################

moved {
  from = aws_iam_role.task_execution
  to   = aws_iam_role.execution
}

moved {
  from = aws_iam_policy.task_ex_role
  to   = aws_iam_policy.execution
}

moved {
  from = aws_iam_role_policy_attachment.task_ex_role
  to   = aws_iam_role_policy_attachment.execution
}

moved {
  from = aws_iam_role_policy_attachment.task_execution
  to   = aws_iam_role_policy_attachment.execution_managed
}

