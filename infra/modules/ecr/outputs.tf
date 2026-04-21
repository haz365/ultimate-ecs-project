# ═══════════════════════════════════════════════════════════════
# ECR MODULE — OUTPUTS
# ═══════════════════════════════════════════════════════════════

output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.arn
  }
}