locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── 1. Compute role (EC2) ──────────────────────────────────────────────────────

resource "aws_iam_role" "compute" {
  name = "${local.name_prefix}-compute-role"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "compute" {
  name = "${local.name_prefix}-compute-policy"
  tags = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Sid    = "RDSConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [var.rds_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "compute" {
  role       = aws_iam_role.compute.name
  policy_arn = aws_iam_policy.compute.arn
}

resource "aws_iam_instance_profile" "compute" {
  name = "${local.name_prefix}-compute-profile"
  role = aws_iam_role.compute.name
  tags = local.tags
}

# ── 2. Async consumer role (Lambda) ───────────────────────────────────────────

resource "aws_iam_role" "async_consumer" {
  name = "${local.name_prefix}-async-consumer-role"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "async_consumer" {
  name = "${local.name_prefix}-async-consumer-policy"
  tags = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [var.sqs_queue_arn]
      },
      {
        Sid    = "S3WriteResults"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = ["${var.s3_bucket_arn}/results/*"]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "async_consumer" {
  role       = aws_iam_role.async_consumer.name
  policy_arn = aws_iam_policy.async_consumer.arn
}

# ── 3. Scheduler role (EventBridge Scheduler) ─────────────────────────────────

resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-scheduler-role"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "scheduler" {
  name = "${local.name_prefix}-scheduler-policy"
  tags = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeTarget"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [var.eventbridge_target_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler.arn
}

# ── 4. CI runner role (GitHub Actions — OIDC trust added in Demo 2) ───────────
#
# Trust policy is a placeholder here: it uses a conditions-ready structure
# but sets the principal to the account root until the OIDC provider is
# provisioned in Demo 2.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "ci_runner" {
  name = "${local.name_prefix}-ci-runner-role"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # Placeholder — replaced with the OIDC provider ARN in Demo 2
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ci_runner" {
  name = "${local.name_prefix}-ci-runner-policy"
  tags = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/dev/*"
        ]
      },
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project}-tf-locks"
        ]
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ECSDeployment"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:RegisterTaskDefinition"
        ]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ci_runner" {
  role       = aws_iam_role.ci_runner.name
  policy_arn = aws_iam_policy.ci_runner.arn
}
