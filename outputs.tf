# ── Outputs wired from the IAM module ─────────────────────────────────────────
# Other modules consume these ARNs rather than hard-coding role names.

output "compute_role_arn" {
  value = module.iam.compute_role_arn
}

output "async_consumer_role_arn" {
  value = module.iam.async_consumer_role_arn
}

output "scheduler_role_arn" {
  value = module.iam.scheduler_role_arn
}

output "ci_runner_role_arn" {
  value = module.iam.ci_runner_role_arn
}
