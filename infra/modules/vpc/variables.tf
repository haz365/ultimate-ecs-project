# ═══════════════════════════════════════════════════════════════
# VPC MODULE — INPUTS
# ═══════════════════════════════════════════════════════════════

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
}

variable "vpc_cidr" {
  description = "IP range for the VPC e.g. 10.0.0.0/16"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}