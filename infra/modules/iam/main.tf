# ═══════════════════════════════════════════════════════════════
# IAM MODULE
# Creates roles for each ECS service
#
# Each service gets TWO roles:
#
# 1. TASK EXECUTION ROLE
#    Used by ECS infrastructure to START the container:
#    - Pull image from ECR
#    - Send logs to CloudWatch
#    - Fetch secrets from Secrets Manager
#
# 2. TASK ROLE
#    Used by your APPLICATION CODE at runtime:
#    - api: publish to SQS, read secrets
#    - worker: consume SQS, read secrets
#    - dashboard: read secrets
#
# Principle: each service gets ONLY what it needs
# ═══════════════════════════════════════════════════════════════


# ─── Shared: Task Execution Role ──────────────────────────────
# All three services share the same execution role
# (they all need to pull from ECR and write logs)

resource "aws_iam_role" "task_execution" {
  name = "${var.project}-${var.environment}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project}-${var.environment}-task-execution-role"
  }
}

# Attach the AWS managed policy for ECS task execution
# Grants: ECR pull, CloudWatch logs write
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to fetch secrets from Secrets Manager
# Containers use this to get DB password + Redis token at startup
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "${var.project}-${var.environment}-execution-secrets-policy"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        var.rds_secret_arn,
        var.redis_secret_arn
      ]
    }]
  })
}


# ─── API Service Task Role ────────────────────────────────────
# What the api app code is allowed to do at runtime

resource "aws_iam_role" "api_task" {
  name = "${var.project}-${var.environment}-api-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project}-${var.environment}-api-task-role"
  }
}

resource "aws_iam_role_policy" "api_task" {
  name = "${var.project}-${var.environment}-api-task-policy"
  role = aws_iam_role.api_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # API publishes click events to SQS
        Sid    = "SQSPublish"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        # SSM Session Manager access for debugging
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}


# ─── Worker Service Task Role ─────────────────────────────────
# What the worker app code is allowed to do at runtime

resource "aws_iam_role" "worker_task" {
  name = "${var.project}-${var.environment}-worker-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project}-${var.environment}-worker-task-role"
  }
}

resource "aws_iam_role_policy" "worker_task" {
  name = "${var.project}-${var.environment}-worker-task-policy"
  role = aws_iam_role.worker_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Worker consumes and deletes messages from SQS
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        # SSM Session Manager access for debugging
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}


# ─── Dashboard Service Task Role ──────────────────────────────
# Dashboard only reads from the database — no SQS needed

resource "aws_iam_role" "dashboard_task" {
  name = "${var.project}-${var.environment}-dashboard-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project}-${var.environment}-dashboard-task-role"
  }
}

resource "aws_iam_role_policy" "dashboard_task" {
  name = "${var.project}-${var.environment}-dashboard-task-policy"
  role = aws_iam_role.dashboard_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SSM Session Manager access for debugging
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}