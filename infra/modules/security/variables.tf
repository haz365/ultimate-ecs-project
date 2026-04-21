variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID — security groups must live inside a VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — used to restrict endpoint access"
  type        = string
}