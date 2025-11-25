# Why `AmazonECS_FullAccess` Is a Security Risk

## Executive Summary

The `AmazonECS_FullAccess` AWS managed policy is **overly permissive** and should **never be used in production**. This document explains why, and provides secure alternatives.

---

## What Is `AmazonECS_FullAccess`?

`AmazonECS_FullAccess` (ARN: `arn:aws:iam::aws:policy/AmazonECS_FullAccess`) is an AWS-managed IAM policy that grants **full administrative access** to Amazon ECS and several related services.

### The Full Policy (Simplified)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "ecr:*",
        "logs:*",
        "cloudwatch:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "iam:PassRole",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "application-autoscaling:*",
        "sns:ListTopics",
        "events:*",
        "servicediscovery:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## ❌ Why This Is Dangerous

### 1. Violates the Principle of Least Privilege

**Least Privilege** = Grant only the permissions needed to perform a task.

| What the Scheduler Needs | What `AmazonECS_FullAccess` Grants |
|--------------------------|-----------------------------------|
| `ecs:RunTask` (1 action) | `ecs:*` (50+ actions) |
| Specific task definition | All task definitions |
| Specific cluster | All clusters in account |

**The scheduler only needs to run tasks, but gets permission to delete your entire infrastructure.**

---

### 2. Destructive Actions Included

`ecs:*` includes these destructive actions:

```
❌ ecs:DeleteCluster          - Delete entire ECS clusters
❌ ecs:DeleteService          - Delete running services
❌ ecs:DeregisterTaskDefinition - Remove task definitions
❌ ecs:DeregisterContainerInstance - Remove EC2 instances from cluster
❌ ecs:StopTask               - Stop any running task
❌ ecs:UpdateService          - Modify any service configuration
```

**Real-World Risk:** If the scheduler's credentials are compromised (leaked in logs, stolen from CI/CD, etc.), an attacker could:
- Delete all your ECS clusters
- Stop all running services
- Cause complete application outage

---

### 3. Cross-Service Permissions

The policy grants access to services beyond ECS:

| Service | Actions Granted | Risk |
|---------|-----------------|------|
| **CloudWatch Logs** | `logs:*` | Delete all logs, hide attack evidence |
| **CloudWatch** | `cloudwatch:*` | Delete alarms, disable monitoring |
| **Load Balancers** | `elasticloadbalancing:*` | Redirect traffic, delete load balancers |
| **Auto Scaling** | `autoscaling:*` | Disable scaling, cause outages |
| **EventBridge** | `events:*` | Delete event rules, break automation |
| **ECR** | `ecr:*` | Delete container images |

---

### 4. No Resource Scoping

```json
"Resource": "*"
```

This means the permissions apply to **every resource in the AWS account**, not just the scheduler's resources.

**Example Attack Scenario:**
1. Attacker compromises the scheduler's IAM role
2. Uses `ecs:RunTask` to run a malicious container
3. Uses `ecs:DeleteService` to delete your production services
4. Uses `logs:DeleteLogGroup` to delete evidence
5. Uses `cloudwatch:DeleteAlarms` to prevent alerts

---

## 📊 Permission Comparison

### Original (Dangerous)

```hcl
resource "aws_iam_role_policy_attachment" "ra" {
  role       = aws_iam_role.ecs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}
```

**Grants:** 100+ actions across 10+ services on all resources

### Improved (Secure)

```hcl
data "aws_iam_policy_document" "scheduler_permissions" {
  # Only ecs:RunTask, scoped to specific task definition
  statement {
    actions   = ["ecs:RunTask"]
    resources = ["${var.task_definition_arn}:*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }
  
  # Only ecs:TagResource, with conditions
  statement {
    actions   = ["ecs:TagResource"]
    resources = [var.ecs_cluster_arn, "arn:aws:ecs:*:*:task/${var.cluster_name}/*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RunTask"]
    }
  }
  
  # Only sqs:SendMessage to specific DLQ
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
  
  # Only iam:PassRole with conditions
  statement {
    actions   = ["iam:PassRole"]
    resources = [var.task_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
```

**Grants:** 4 specific actions on specific resources with conditions

---

## 🔢 By the Numbers

| Metric | `AmazonECS_FullAccess` | Least Privilege |
|--------|------------------------|-----------------|
| ECS Actions | 50+ | 2 |
| Other Service Actions | 50+ | 2 |
| Total Actions | 100+ | 4-6 |
| Resource Scope | `*` (everything) | Specific ARNs |
| IAM Conditions | None | 3+ conditions |
| Blast Radius | Entire account | Single task |

---

## 🛡️ AWS Security Best Practices Violated

### AWS Well-Architected Framework - Security Pillar

> **SEC03-BP02: Grant least privilege access**
> 
> "Grant only the access that identities require to perform specific actions on specific resources under specific conditions."

Source: [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_least_privileges.html)

### AWS IAM Best Practices

> "When you create IAM policies, follow the standard security advice of granting least privilege, or granting only the permissions required to perform a task."

Source: [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege)

---

## 🚨 Real-World Incidents

### Capital One Data Breach (2019)

While not directly ECS-related, this breach involved overly permissive IAM roles:
- Attacker exploited a misconfigured WAF
- Overly permissive IAM role allowed access to S3 buckets
- **100 million customer records exposed**
- **$80 million fine** from OCC

**Lesson:** Least privilege could have limited the blast radius.

### Common Attack Pattern

```
1. Compromise application credentials (leaked in logs, CI/CD, etc.)
2. Enumerate permissions using aws iam get-user, sts get-caller-identity
3. If ecs:* found, attacker can:
   - Run crypto-mining containers
   - Exfiltrate data via containers
   - Delete services for ransom
   - Pivot to other resources
```

---

## ✅ Secure Alternatives

### Option 1: Custom Inline Policy (Recommended)

Create a policy with only the needed permissions:

```hcl
resource "aws_iam_role_policy" "scheduler" {
  name   = "scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_permissions.json
}
```

### Option 2: Customer Managed Policy

If you need to share the policy across multiple roles:

```hcl
resource "aws_iam_policy" "scheduler" {
  name   = "ecs-scheduler-policy"
  policy = data.aws_iam_policy_document.scheduler_permissions.json
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler.arn
}
```

### Option 3: Use AWS Service-Linked Roles

For some use cases, AWS provides pre-configured service-linked roles:
- `AWSServiceRoleForECS` - For ECS service operations
- `AWSServiceRoleForApplicationAutoScaling_ECSService` - For auto-scaling

---

## 📋 Checklist: Is Your Policy Secure?

- [ ] No `*` actions (like `ecs:*`)
- [ ] No `Resource: "*"` (scope to specific ARNs)
- [ ] Uses IAM conditions where possible
- [ ] Only grants permissions actually needed
- [ ] Reviewed and audited regularly
- [ ] No AWS managed `*FullAccess` policies attached

---

## 🔍 How to Audit Your Current Permissions

### Check for FullAccess Policies

```bash
# List all roles with FullAccess policies attached
aws iam list-entities-for-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess \
  --query 'PolicyRoles[].RoleName'
```

### Use IAM Access Analyzer

AWS IAM Access Analyzer can identify overly permissive policies:
1. Go to IAM Console → Access Analyzer
2. Create an analyzer
3. Review findings for external access and unused permissions

### Use AWS Config Rules

Enable these AWS Config rules:
- `iam-policy-no-statements-with-admin-access`
- `iam-policy-no-statements-with-full-access`

---

## Summary

| Aspect | `AmazonECS_FullAccess` | Least Privilege |
|--------|------------------------|-----------------|
| **Security** | ❌ Dangerous | ✅ Secure |
| **Compliance** | ❌ Fails audits | ✅ Passes audits |
| **Blast Radius** | 🔴 Entire account | 🟢 Single resource |
| **AWS Best Practice** | ❌ Violates | ✅ Follows |
| **Maintenance** | Easy (one policy) | Requires effort |

**The small extra effort to create least-privilege policies is worth the significant security improvement.**

---

## References

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [AWS ECS Security Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security.html)
- [OWASP - Principle of Least Privilege](https://owasp.org/www-community/Access_Control)

