output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "ecr_repository_urls" {
  description = "ECR URLs for each service"
  value       = module.ecr.repository_urls
}

output "alb_sg_id" {
  value = module.security.alb_sg_id
}

output "api_sg_id" {
  value = module.security.api_sg_id
}
