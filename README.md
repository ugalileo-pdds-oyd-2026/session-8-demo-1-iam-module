# Session 8 — IAM as Code: building `modules/iam/`

Refactor four over-permissioned inline IAM resources into a reusable Terraform module that enforces least-privilege by construction, using `jsonencode` trust and permissions policies.

## What students learn

- The difference between IAM Users/Groups (human identities) and Roles (workload identities), and why workloads always use Roles
- How a policy document is structured: `Version`, `Statement`, `Sid`, `Effect`, `Action`, `Resource`, and `Principal`
- The difference between a trust policy (who can assume a role) and a permissions policy (what the role can do)
- Why EC2 instances need an `aws_iam_instance_profile` in addition to the role itself
- How to scope permissions to specific ARNs and path prefixes instead of using `Resource: "*"`
- When a wildcard resource is justified (ECR auth tokens, CloudWatch Logs) versus lazy

## Project structure

```
modules/iam/
  main.tf        # 4 roles, 4 policies, 4 attachments, 1 instance profile
  variables.tf   # ARN inputs that define each role's scope
  outputs.tf     # role ARNs consumed by other modules
main.tf          # root: module call + output pass-through
variables.tf     # root variables including github_repo
outputs.tf       # root outputs
versions.tf
.github/workflows/
  terraform-ci.yml
```

## Prerequisites

- [Terraform >= 1.6](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured with credentials for your target account
- A `dev.tfvars` file with values for: `project`, `environment`, `s3_bucket_arn`, `rds_arn`, `sqs_queue_arn`, `eventbridge_target_arn`, `github_repo`

## Demo workflow

### 1. Observe the starting point

Look at the root `main.tf` — it has four inline IAM roles using `Action = ["*"]` or `Resource = "*"`. This is what the module replaces.

```bash
cat main.tf
```

### 2. Create the module scaffold

```bash
mkdir -p modules/iam
touch modules/iam/main.tf modules/iam/variables.tf modules/iam/outputs.tf
```

### 3. Write `modules/iam/variables.tf`

Each variable is a specific resource ARN. This forces every caller to declare exactly which resources the module will touch.

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the application S3 bucket"
}

variable "rds_arn" {
  type        = string
  description = "ARN of the RDS instance"
}

variable "sqs_queue_arn" {
  type        = string
  description = "ARN of the SQS queue consumed by the async worker"
}

variable "eventbridge_target_arn" {
  type        = string
  description = "ARN of the target invoked by the EventBridge Scheduler rule"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in org/name format — used to scope CI runner trust"
}
```

### 4. Stub `modules/iam/outputs.tf`

```hcl
output "compute_role_arn" {
  value = aws_iam_role.compute.arn
}

output "async_consumer_role_arn" {
  value = aws_iam_role.async_consumer.arn
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}

output "ci_runner_role_arn" {
  value = aws_iam_role.ci_runner.arn
}
```

### 5. Add the compute role (EC2) to `modules/iam/main.tf`

The trust policy allows EC2 to assume the role. The permissions policy grants four specific S3 actions on one bucket and `rds-db:connect` on one instance. The instance profile is required to attach the role to an EC2 instance.

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

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
        Sid      = "RDSConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
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
```

### 6. Add the async consumer role (Lambda)

The S3 resource is scoped to the `results/*` path prefix — the Lambda can write results but cannot touch other prefixes. CloudWatch Logs keeps a wildcard because Lambda writes to dynamically-named log groups.

```hcl
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
        Sid      = "S3WriteResults"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
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
```

### 7. Add the scheduler role (EventBridge Scheduler)

One action, one resource — the purest example of least-privilege in the module.

```hcl
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
```

### 8. Add the CI runner role (placeholder OIDC trust)

The trust policy uses account root as a placeholder — this will be replaced with a real OIDC provider in Demo 2. ECR and ECS keep `Resource: "*"` because ECR auth tokens are account-scoped and ECS task definitions don't have predictable ARNs at module-write time.

```hcl
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
        # Placeholder — replaced with the OIDC provider in Demo 2
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
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ci_runner" {
  role       = aws_iam_role.ci_runner.name
  policy_arn = aws_iam_policy.ci_runner.arn
}
```

### 9. Wire the module in root `main.tf`

Replace the four inline role resources with a single module call. Other modules consume the role ARNs via outputs — they never reference a role by name.

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "iam" {
  source = "./modules/iam"

  project                = var.project
  environment            = var.environment
  s3_bucket_arn          = var.s3_bucket_arn
  rds_arn                = var.rds_arn
  sqs_queue_arn          = var.sqs_queue_arn
  eventbridge_target_arn = var.eventbridge_target_arn
  github_repo            = var.github_repo
}

output "compute_role_arn"         { value = module.iam.compute_role_arn }
output "async_consumer_role_arn"  { value = module.iam.async_consumer_role_arn }
output "scheduler_role_arn"       { value = module.iam.scheduler_role_arn }
output "ci_runner_role_arn"       { value = module.iam.ci_runner_role_arn }
```

### 10. Format, validate, and plan

```bash
terraform fmt -recursive
terraform init -upgrade
terraform validate
terraform plan -var-file=dev.tfvars
```

Expected output:

```
Success! The configuration is valid.

Plan: 13 to add, 0 to change, 0 to destroy.
# (4 roles + 4 policies + 4 attachments + 1 instance profile)
```

### 11. Clean up

```bash
terraform destroy -var-file=dev.tfvars
```

## Expected outcomes

By the end of this demo, students should be able to:

1. Explain the difference between IAM Users/Groups and Roles, and why all workloads in this course use Roles
2. Read and write a policy document using the full `Statement` anatomy (`Sid`, `Effect`, `Action`, `Resource`, `Principal`)
3. Distinguish a trust policy from a permissions policy and identify which Terraform attribute holds each
4. Scope permissions to specific ARNs and path prefixes to enforce least-privilege
5. Identify when `Resource: "*"` is justified (unknowable ARNs at write time) vs. lazy
6. Encapsulate all IAM resources in a Terraform module and expose role ARNs as outputs
