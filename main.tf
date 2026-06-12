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
