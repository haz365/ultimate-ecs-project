# ═══════════════════════════════════════════════════════════════
# SECURITY MODULE
# Creates security groups for every layer of the architecture
#
# Security groups are virtual firewalls — they control which
# traffic is allowed in and out of each resource
#
# Layers:
#   1. ALB      — accepts HTTPS from internet only
#   2. API      — accepts traffic from ALB only
#   3. Worker   — no inbound (it pulls from SQS, never receives)
#   4. Dashboard — accepts traffic from ALB only
#   5. RDS      — accepts PostgreSQL from ECS tasks only
#   6. Redis    — accepts Redis port from ECS tasks only
# ═══════════════════════════════════════════════════════════════


# ─── ALB Security Group ───────────────────────────────────────
# The ONLY security group that accepts traffic from 0.0.0.0/0
# All other security groups only accept from each other
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "ALB — allows HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  # Allow HTTP — redirected to HTTPS by the listener
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS — the only port that serves real traffic
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound so ALB can forward to ECS tasks
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-alb-sg"
  }
}


# ─── API Service Security Group ───────────────────────────────
# Only accepts traffic from the ALB
# Internet cannot reach the API container directly
resource "aws_security_group" "api" {
  name        = "${var.project}-${var.environment}-api-sg"
  description = "API service — allows traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB on port 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound - needed for VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-api-sg"
  }
}


# ─── Worker Security Group ────────────────────────────────────
# Worker has NO inbound rules — it never receives traffic
# It only makes outbound calls to SQS and RDS via VPC endpoints
resource "aws_security_group" "worker" {
  name        = "${var.project}-${var.environment}-worker-sg"
  description = "Worker service — outbound only"
  vpc_id      = var.vpc_id

  # No ingress rules — worker is pull-based (polls SQS)
  # Nobody connects TO the worker

  egress {
    description = "All outbound - needed for SQS and RDS via VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-worker-sg"
  }
}


# ─── Dashboard Security Group ─────────────────────────────────
# Only accepts traffic from ALB on port 8081
resource "aws_security_group" "dashboard" {
  name        = "${var.project}-${var.environment}-dashboard-sg"
  description = "Dashboard service — allows traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB on port 8081"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-dashboard-sg"
  }
}


# ─── RDS Security Group ───────────────────────────────────────
# Only accepts PostgreSQL connections from ECS tasks
# Nobody else can connect to the database
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS — allows PostgreSQL from ECS tasks only"
  vpc_id      = var.vpc_id

  # Allow from api service
  ingress {
    description     = "PostgreSQL from api service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  # Allow from worker service
  ingress {
    description     = "PostgreSQL from worker service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  # Allow from dashboard service
  ingress {
    description     = "PostgreSQL from dashboard service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dashboard.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-rds-sg"
  }
}


# ─── Redis Security Group ─────────────────────────────────────
# Only accepts Redis connections from the API service
# (only api uses Redis for caching)
resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-redis-sg"
  description = "Redis — allows connections from api service only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from api service"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-redis-sg"
  }
}