# ── Existing infrastructure from prior sessions ────────────────────────────────

# IAM roles are currently inline here — no module, no scoping.
# This is the "security gap" we are closing in this demo.

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── Compute role (EC2) — problem: Action = * ──────────────────────────────────

resource "aws_iam_role" "compute" {
  name = "${var.project}-compute-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "compute_access" {
  name = "${var.project}-compute-access"
  tags = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Access"
        Effect   = "Allow"
        Action   = ["s3:*"]      # ← too broad
        Resource = "*"           # ← no bucket constraint
      },
      {
        Sid      = "RDSAccess"
        Effect   = "Allow"
        Action   = ["rds:*"]     # ← too broad
        Resource = "*"           # ← no instance constraint
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "compute" {
  role       = aws_iam_role.compute.name
  policy_arn = aws_iam_policy.compute_access.arn
}

# ── Async consumer role (SQS / Lambda) — problem: no resource constraint ──────

resource "aws_iam_role" "async_consumer" {
  name = "${var.project}-async-consumer-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "async_consumer_access" {
  name = "${var.project}-async-consumer-access"
  tags = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:*", "s3:*"]   # ← too broad; no ARN constraint
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "async_consumer" {
  role       = aws_iam_role.async_consumer.name
  policy_arn = aws_iam_policy.async_consumer_access.arn
}

# ── Scheduler role (EventBridge Scheduler) ───────────────────────────────────

resource "aws_iam_role" "scheduler" {
  name = "${var.project}-scheduler-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "scheduler_access" {
  name = "${var.project}-scheduler-access"
  tags = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:*"]   # ← too broad
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler_access.arn
}

# ── CI runner role — problem: no OIDC trust, wildcard perms ──────────────────

resource "aws_iam_role" "ci_runner" {
  name = "${var.project}-ci-runner-role"
  tags = local.common_tags

  # This is wrong: hard-coded account root trust is too permissive.
  # Will be replaced with OIDC federation in Demo 2.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::ACCOUNT_ID:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ci_runner_access" {
  name = "${var.project}-ci-runner-access"
  tags = local.common_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["*"]   # ← admin-equivalent — this is the worst offender
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ci_runner" {
  role       = aws_iam_role.ci_runner.name
  policy_arn = aws_iam_policy.ci_runner_access.arn
}
