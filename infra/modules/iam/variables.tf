variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  description = "AWS account ID — used to scope IAM policies"
  type        = string
}

variable "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS password"
  type        = string
}

variable "redis_secret_arn" {
  description = "Secrets Manager ARN for Redis auth token"
  type        = string
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN — worker needs access"
  type        = string
}