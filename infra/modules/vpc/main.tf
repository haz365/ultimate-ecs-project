# ═══════════════════════════════════════════════════════════════
# VPC MODULE
# Creates all networking for one environment
#
# KEY DIFFERENCE from previous projects:
# NO NAT Gateway — VPC Endpoints instead
# Private subnets reach AWS services directly without internet
#
# What we create:
#   - VPC across 3 AZs
#   - 3 public subnets  (ALB lives here)
#   - 3 private subnets (ECS tasks live here)
#   - Internet Gateway  (public subnet internet access)
#   - VPC Endpoints     (private AWS service access)
#   - VPC Flow Logs     (required by security posture)
# ═══════════════════════════════════════════════════════════════

# ─── Availability Zones ──────────────────────────────────────
# Fetch all available AZs in the region
# We use the first 3 for our subnets
data "aws_availability_zones" "available" {
  state = "available"
}

# ─── VPC ─────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true   # Required for VPC endpoints to work
  enable_dns_support   = true   # Required for VPC endpoints to work

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

# ─── Public Subnets ──────────────────────────────────────────
# One per AZ — ALB must span at least 2 AZs
# NAT Gateway would live here in the old approach
# Now we only put the ALB here

resource "aws_subnet" "public" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Resources here get public IPs (ALB needs this)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"
    Tier = "public"
  }
}

# ─── Private Subnets ─────────────────────────────────────────
# One per AZ — ECS tasks live here
# No public IPs, no direct internet access
# Reach AWS services via VPC endpoints

resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-private-${count.index + 1}"
    Tier = "private"
  }
}

# ─── Internet Gateway ─────────────────────────────────────────
# The front door for the public subnet (ALB needs this)
# Private subnets do NOT use this

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# ─── Route Table: Public ──────────────────────────────────────
# Public subnets route internet traffic via IGW

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─── Route Table: Private ─────────────────────────────────────
# Private subnets have NO default internet route
# Traffic to AWS services goes via VPC endpoints (defined below)
# Everything else is blocked — this is the security win

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Deliberately no 0.0.0.0/0 route
  # Private subnets cannot reach the internet

  tags = {
    Name = "${var.project}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── VPC Flow Logs ───────────────────────────────────────────
# Logs ALL network traffic in/out of the VPC
# Required by the security posture — helps detect intrusions
# Goes to CloudWatch Logs

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project}-${var.environment}"
  retention_in_days = 30   # Keep 30 days of network logs

  tags = {
    Name = "${var.project}-${var.environment}-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project}-${var.environment}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"   # Log accepted AND rejected traffic
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name = "${var.project}-${var.environment}-flow-log"
  }
}


# ═══════════════════════════════════════════════════════════════
# VPC ENDPOINTS
# This is what replaces the NAT Gateway
# Each endpoint creates a private connection to an AWS service
# Traffic never leaves the AWS network
# ═══════════════════════════════════════════════════════════════

# ─── Security Group for Interface Endpoints ───────────────────
# Interface endpoints need a security group
# Allow HTTPS (443) from within the VPC only

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpc-endpoints-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-vpc-endpoints-sg"
  }
}

# ─── S3 Gateway Endpoint ──────────────────────────────────────
# Gateway type = free, no hourly charge
# ECR uses S3 internally to store image layers
# So we need this for docker pulls to work

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"   # Gateway = free

  # Add to private route table so private subnets can use it
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project}-${var.environment}-s3-endpoint"
  }
}

# ─── ECR API Endpoint ─────────────────────────────────────────
# Needed for ECS to authenticate with ECR
# (the API calls that happen before actually pulling the image)

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"   # Interface = has a private IP in your subnet
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true   # So ecr.amazonaws.com resolves to private IP

  tags = {
    Name = "${var.project}-${var.environment}-ecr-api-endpoint"
  }
}

# ─── ECR Docker Endpoint ──────────────────────────────────────
# Needed for actually pulling the Docker image layers

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-ecr-dkr-endpoint"
  }
}

# ─── CloudWatch Logs Endpoint ─────────────────────────────────
# Needed for containers to send logs to CloudWatch
# Without this, console.log() in your app goes nowhere

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-cloudwatch-logs-endpoint"
  }
}

# ─── SQS Endpoint ────────────────────────────────────────────
# Needed for the api service to publish click events
# and the worker service to consume them

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-sqs-endpoint"
  }
}

# ─── Secrets Manager Endpoint ────────────────────────────────
# Needed for containers to fetch secrets at runtime
# (DB password, Redis token, etc.)

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-secrets-endpoint"
  }
}

# ─── SSM Endpoint ────────────────────────────────────────────
# Needed for SSM Session Manager — our only way to
# access containers for break-glass debugging
# No bastion host needed — SSM is more secure

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${var.environment}-ssm-messages-endpoint"
  }
}