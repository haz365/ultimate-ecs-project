output "task_execution_role_arn" {
  description = "Shared task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "api_task_role_arn" {
  description = "API service task role ARN"
  value       = aws_iam_role.api_task.arn
}

output "worker_task_role_arn" {
  description = "Worker service task role ARN"
  value       = aws_iam_role.worker_task.arn
}

output "dashboard_task_role_arn" {
  description = "Dashboard service task role ARN"
  value       = aws_iam_role.dashboard_task.arn
}