variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket created in Session 4"
}

variable "rds_arn" {
  type        = string
  description = "ARN of the RDS instance created in Session 4"
}

variable "sqs_queue_arn" {
  type        = string
  description = "ARN of the SQS queue created in Session 7"
}

variable "eventbridge_target_arn" {
  type        = string
  description = "ARN of the Lambda function targeted by the EventBridge rule"
}
