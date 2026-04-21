# ═══════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLES
# Values set in terraform.tfvars per environment
# ═══════════════════════════════════════════════════════════════

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name: dev, staging, or prod"
  type        = string
}

variable "project" {
  description = "Project name — used as prefix for all resources"
  type        = string
  default     = "ultimate-ecs"
}

variable "vpc_cidr" {
  description = "IP range for the VPC"
  type        = string
}

variable "github_org" {
  description = "GitHub username or organisation"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "domain_name" {
  description = "Base domain e.g. mydomain.com"
  type        = string
}