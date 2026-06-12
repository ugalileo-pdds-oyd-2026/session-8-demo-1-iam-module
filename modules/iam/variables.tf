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
  description = "GitHub repository in org/name format — used to scope the CI runner trust policy"
}
