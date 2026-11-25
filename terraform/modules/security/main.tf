data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- KMS CMK for Storage (S3, Aurora, ElastiCache, Secrets Manager) ---
resource "aws_kms_key" "storage" {
  description             = "KMS CMK for Enterprise RAG storage encryption (Aurora, S3, ElastiCache, Secrets)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchAndS3ServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "rds.amazonaws.com",
            "secretsmanager.amazonaws.com",
            "logs.${data.aws_region.current.name}.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-storage-kms"
  }
}

resource "aws_kms_alias" "storage" {
  name          = "alias/${var.project_name}-${var.environment}-storage"
  target_key_id = aws_kms_key.storage.key_id
}

# --- KMS CMK for Compute & Logs (Lambda, SQS, CloudWatch) ---
resource "aws_kms_key" "compute_logs" {
  description             = "KMS CMK for Enterprise RAG compute, messaging, and logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowLogsAndComputeServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "logs.${data.aws_region.current.name}.amazonaws.com",
            "lambda.amazonaws.com",
            "sqs.amazonaws.com",
            "states.${data.aws_region.current.name}.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-compute-kms"
  }
}

resource "aws_kms_alias" "compute_logs" {
  name          = "alias/${var.project_name}-${var.environment}-compute"
  target_key_id = aws_kms_key.compute_logs.key_id
}

# --- Security Groups (Strict Principle of Least Privilege) ---

# 1. Lambda Workload Security Group
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.environment}-lambda-sg"
  description = "Security group for RAG ingestion and query Lambdas"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  }
}

# 2. Aurora PostgreSQL Security Group
resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-sg"
  description = "Security group for Aurora PostgreSQL pgvector"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL access from Lambda workloads only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "No egress required for isolated Aurora cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"] # Null route
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  }
}

# 3. ElastiCache Redis Security Group
resource "aws_security_group" "elasticache" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis semantic cache"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis port 6379 from Lambda workloads only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "No egress required for Redis cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-sg"
  }
}

# 4. VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "Security group for PrivateLink VPC Endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS inbound from Lambda workloads to PrivateLink endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "Egress to private subnet responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-sg"
  }
}

# --- Lambda Egress Rules (Restricted to Internal Services Only) ---
resource "aws_security_group_rule" "lambda_to_aurora" {
  type                     = "egress"
  description              = "Allow outbound to Aurora PostgreSQL"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.aurora.id
}

resource "aws_security_group_rule" "lambda_to_redis" {
  type                     = "egress"
  description              = "Allow outbound to ElastiCache Redis"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.elasticache.id
}

resource "aws_security_group_rule" "lambda_to_vpce" {
  type                     = "egress"
  description              = "Allow outbound HTTPS to VPC Interface Endpoints"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.vpc_endpoints.id
}
