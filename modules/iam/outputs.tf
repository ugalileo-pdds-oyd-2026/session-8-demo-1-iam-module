output "compute_role_arn" {
  description = "ARN of the EC2 compute role — attach to EC2 instance profile"
  value       = aws_iam_role.compute.arn
}

output "async_consumer_role_arn" {
  description = "ARN of the Lambda async consumer role"
  value       = aws_iam_role.async_consumer.arn
}

output "scheduler_role_arn" {
  description = "ARN of the EventBridge Scheduler execution role"
  value       = aws_iam_role.scheduler.arn
}

output "ci_runner_role_arn" {
  description = "ARN of the GitHub Actions CI runner role"
  value       = aws_iam_role.ci_runner.arn
}
