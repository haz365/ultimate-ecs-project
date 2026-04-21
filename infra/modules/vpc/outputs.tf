# ═══════════════════════════════════════════════════════════════
# VPC MODULE — OUTPUTS
# These values are consumed by other modules
# ═══════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "VPC ID — needed by security groups, endpoints, etc."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block — used in security group rules"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs — ALB lives here"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — ECS tasks live here"
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "Private route table ID — VPC gateway endpoints attach here"
  value       = aws_route_table.private.id
}

output "vpc_endpoints_sg_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}