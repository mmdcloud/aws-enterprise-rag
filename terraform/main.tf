# ==============================================================================
# AWS Enterprise RAG: Production Infrastructure Architecture
# ==============================================================================
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# 1. Security & Encryption Subsystem (KMS CMKs, Least-Privilege Security Groups)
module "storage_kms" {
  source = "./modules/kms"

  name                    = "${var.project_name}-${var.environment}-storage"
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
}

# --- KMS CMK for Compute & Logs (Lambda, SQS, CloudWatch) ---
module "compute_logs_kms" {
  source = "./modules/kms"

  name                    = "${var.project_name}-${var.environment}-compute"
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
}

# --- Security Groups (Strict Principle of Least Privilege via modules/security-groups) ---

# 1. Lambda Workload Security Group
module "lambda_sg" {
  source = "./modules/security-groups"

  name          = "${var.project_name}-${var.environment}-lambda-sg"
  vpc_id        = module.vpc.vpc_id
  ingress_rules = []
  egress_rules = [
    {
      description = "Allow outbound to Aurora PostgreSQL"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    },
    {
      description = "Allow outbound to ElastiCache Redis"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    },
    {
      description = "Allow outbound HTTPS to VPC Interface Endpoints"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  }
}

# 2. Aurora PostgreSQL Security Group
module "aurora_sg" {
  source = "./modules/security-groups"

  name   = "${var.project_name}-${var.environment}-aurora-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      description     = "PostgreSQL access from Lambda workloads only"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [module.lambda_sg.id]
      cidr_blocks     = []
    }
  ]

  egress_rules = [
    {
      description = "No egress required for isolated Aurora cluster"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["127.0.0.1/32"]
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  }
}

# 3. ElastiCache Redis Security Group
module "elasticache_sg" {
  source = "./modules/security-groups"

  name   = "${var.project_name}-${var.environment}-redis-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      description     = "Redis port 6379 from Lambda workloads only"
      from_port       = 6379
      to_port         = 6379
      protocol        = "tcp"
      security_groups = [module.lambda_sg.id]
      cidr_blocks     = []
    }
  ]

  egress_rules = [
    {
      description = "No egress required for Redis cluster"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["127.0.0.1/32"]
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-sg"
  }
}

# 4. VPC Endpoints Security Group
module "vpc_endpoints_sg" {
  source = "./modules/security-groups"

  name   = "${var.project_name}-${var.environment}-vpce-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      description     = "HTTPS inbound from Lambda workloads to PrivateLink endpoints"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [module.lambda_sg.id]
      cidr_blocks     = []
    }
  ]

  egress_rules = [
    {
      description = "Egress to private subnet responses"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-sg"
  }
}


# module "security" {
#   source       = "./modules/security"
#   project_name = var.project_name
#   environment  = var.environment
#   vpc_id       = module.vpc.vpc_id
# }

# 2. VPC Network Subsystem (Multi-AZ, Isolated Database Tier, VPC Flow Logs)
module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway
  kms_key_arn        = module.compute_logs_kms.arn
}

# 3. VPC Endpoints (AWS PrivateLink: Zero Public Internet Exposure)
locals {
  interface_services = {
    bedrock_runtime = "bedrock-runtime"
    bedrock         = "bedrock"
    secretsmanager  = "secretsmanager"
    comprehend      = "comprehend"
    logs            = "logs"
    monitoring      = "monitoring"
    states          = "states"
    sqs             = "sqs"
    kms             = "kms"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_services
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-${each.key}"
  }
}

# --- S3 Gateway Endpoint (Zero Cost, High Throughput) ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.private_route_table_id]

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-s3-gateway"
  }
}

# module "vpc_endpoints" {
#   source                          = "./modules/vpc_endpoints"
#   project_name                    = var.project_name
#   environment                     = var.environment
#   vpc_id                          = module.vpc.vpc_id
#   private_subnet_ids              = module.vpc.private_subnet_ids
#   private_route_table_id          = module.vpc.private_route_table_id
#   vpc_endpoints_security_group_id = module.security.vpc_endpoints_security_group_id
# }

# 4. Storage & Retrieval Subsystem: Aurora PostgreSQL pgvector
module "aurora_pgvector" {
  source                   = "./modules/aurora_pgvector"
  project_name             = var.project_name
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  database_subnet_ids      = module.vpc.database_subnet_ids
  aurora_security_group_id = module.aurora_sg.id
  kms_key_arn              = module.storage_kms.arn
  database_name            = var.database_name
  min_capacity             = var.aurora_min_capacity
  max_capacity             = var.aurora_max_capacity
}

# 5. Semantic Caching Subsystem: Amazon ElastiCache Serverless (Redis)
module "elasticache_redis" {
  source                  = "./modules/elasticache_redis"
  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  database_subnet_ids     = module.vpc.database_subnet_ids
  redis_security_group_id = module.elasticache_sg.id
  kms_key_arn             = module.storage_kms.arn
}

# 6. Security & Governance: Bedrock Guardrails (Prompt Injection & Topic Defense)
module "bedrock_guardrails" {
  source = "./modules/bedrock/guardrail"

  name                      = "${var.project_name}-${var.environment}-guardrail"
  description               = "Production Bedrock Guardrail with prompt injection defense, PII masking, and topic filtering"
  blocked_input_messaging   = "I am unable to process this request because it violated the enterprise safety and security policy."
  blocked_outputs_messaging = "The generated response was withheld in accordance with enterprise data protection and compliance guidelines."

  # 1. Content Policy Config: Defense against prompt injection, jailbreaks, and harmful content
  content_filters = [
    {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    },
    {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    },
    {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    },
    {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    },
    {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    },
    {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  ]

  # 2. Sensitive Information Policy Config: PII Redaction / Masking / Blocking
  pii_entities = [
    {
      type           = "EMAIL"
      action         = "ANONYMIZE"
      input_action   = "ANONYMIZE"
      output_action  = "ANONYMIZE"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "PHONE"
      action         = "ANONYMIZE"
      input_action   = "ANONYMIZE"
      output_action  = "ANONYMIZE"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "US_SOCIAL_SECURITY_NUMBER"
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "CREDIT_DEBIT_CARD_NUMBER"
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "US_BANK_ACCOUNT_NUMBER"
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "AWS_ACCESS_KEY"
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = true
    },
    {
      type           = "PASSWORD"
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = true
    }
  ]

  # 3. Topic Policy Config: Denied Out-of-Scope Enterprise Topics
  denied_topics = [
    {
      name       = "MaliciousCyberExploitation"
      definition = "Requests providing active vulnerability exploit code, malware authoring, or unauthorized penetration instructions."
      examples = [
        "Write a buffer overflow exploit for CVE-2024-1234",
        "Generate a reverse shell payload to bypass firewalls"
      ]
    },
    {
      name       = "UnauthorizedLegalAdvice"
      definition = "Requests asking the model to provide authoritative legal contracts, formal legal counsel, or binding legal opinions."
      examples = [
        "Provide binding legal advice for my lawsuit",
        "Draft a legally certified power of attorney"
      ]
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-guardrail"
  }
}

# 7. Ingestion Plane: S3, EventBridge, SQS DLQ, Step Functions, Titan Embeddings v2
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  document_bucket_name = "${var.project_name}-${var.environment}-documents-${random_id.bucket_suffix.hex}"
  document_bucket_arn  = "arn:aws:s3:::${local.document_bucket_name}"
}

# --- S3 Document Storage Bucket (via modules/s3) ---
module "documents_bucket" {
  source = "./modules/s3"

  bucket_name             = local.document_bucket_name
  force_destroy           = false
  versioning_enabled      = "Enabled"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          local.document_bucket_arn,
          "${local.document_bucket_arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-documents"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = module.documents_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.storage_kms.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Enable EventBridge notifications for S3 uploads
resource "aws_s3_bucket_notification" "documents" {
  bucket      = module.documents_bucket.bucket
  eventbridge = true
}

# --- Dead Letter Queue (DLQ) for Ingestion Pipeline (via modules/sqs) ---
module "ingestion_dlq" {
  source = "./modules/sqs"

  queue_name                 = "${var.project_name}-${var.environment}-ingestion-dlq"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 0
  policy                     = null

  tags = {
    Name = "${var.project_name}-${var.environment}-ingestion-dlq"
  }
}

# --- Ingestion Lambda Deployment Package ---
data "archive_file" "ingestion_pkg" {
  type        = "zip"
  source_dir  = "${path.root}/../src"
  output_path = "${path.module}/ingestion_lambda.zip"
}

# --- Ingestion Lambda IAM Role & Policy (via modules/iam) ---
module "ingestion_lambda_iam" {
  source = "./modules/iam"

  role_name        = "${var.project_name}-${var.environment}-ingestion-lambda-role"
  role_description = "IAM role for Enterprise RAG Ingestion Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  policy_name        = "${var.project_name}-${var.environment}-ingestion-permissions"
  policy_description = "Least-privilege permissions for Ingestion Lambda (VPC ENIs, S3, Comprehend, Bedrock, Secrets Manager, KMS, CloudWatch)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaVPCAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3DocumentReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          module.documents_bucket.arn,
          "${module.documents_bucket.arn}/*"
        ]
      },
      {
        Sid    = "ComprehendPiiDetection"
        Effect = "Allow"
        Action = [
          "comprehend:DetectPiiEntities",
          "comprehend:DetectEntities"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockEmbeddingInvocation"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_embedding_model_id}"
        ]
      },
      {
        Sid    = "AuroraSecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [module.aurora_pgvector.secret_arn]
      },
      {
        Sid    = "KMSDecryptAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = [
          module.storage_kms.arn,
          module.compute_logs_kms.arn
        ]
      },
      {
        Sid    = "CloudWatchMetricsLogging"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ingestion-lambda-role"
  }
}

# --- Ingestion Lambda Function (via modules/lambda) ---
module "ingestion_lambda" {
  source = "./modules/lambda"

  function_name           = "${var.project_name}-${var.environment}-ingestion-worker"
  role_arn                = module.ingestion_lambda_iam.arn
  handler                 = "ingestion.handler.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.lambda_artifacts_bucket.objects[1].bucket
  s3_key                  = module.lambda_artifacts_bucket.objects[1].key
  code_signing_config_arn = null
  layers                  = []
  permissions             = []

  vpc_config = {
    subnet_ids         = toset(module.vpc.private_subnet_ids)
    security_group_ids = toset([module.lambda_sg.id])
  }

  env_variables = {
    ENVIRONMENT                = var.environment
    AURORA_SECRET_ARN          = module.aurora_pgvector.secret_arn
    AURORA_CLUSTER_ENDPOINT    = module.aurora_pgvector.cluster_endpoint
    DATABASE_NAME              = module.aurora_pgvector.database_name
    BEDROCK_EMBEDDING_MODEL_ID = var.bedrock_embedding_model_id
    CHUNK_SIZE                 = tostring(var.chunk_size)
    CHUNK_OVERLAP              = tostring(var.chunk_overlap)
    EMBEDDING_DIMENSION        = tostring(var.embedding_dimension)
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ingestion-worker"
  }
}

# --- Step Functions IAM Role & Policy (via modules/iam) ---
module "step_functions_iam" {
  source = "./modules/iam"

  role_name        = "${var.project_name}-${var.environment}-sfn-role"
  role_description = "IAM role for Enterprise RAG Step Functions ingestion pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })

  policy_name        = "${var.project_name}-${var.environment}-sfn-policy"
  policy_description = "Permissions for Step Functions to invoke Ingestion Lambda, send to SQS DLQ, and write CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeIngestionLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          module.ingestion_lambda.arn,
          "${module.ingestion_lambda.arn}:*"
        ]
      },
      {
        Sid    = "SQSSendMessageToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [module.ingestion_dlq.arn]
      },
      {
        Sid    = "CloudWatchLogsAndKMS"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "kms:GenerateDataKey*",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-sfn-role"
  }
}

# --- CloudWatch Log Group for Step Functions (via modules/cloudwatch/cloudwatch-log-group) ---
module "sfn_logs" {
  source = "./modules/cloudwatch/cloudwatch-log-group"

  log_group_name    = "/aws/vendedlogs/states/${var.project_name}-${var.environment}-ingestion"
  retention_in_days = 90
  skip_destroy      = false

  tags = {
    Name = "${var.project_name}-${var.environment}-sfn-logs"
  }
}

# --- Step Functions State Machine ---
resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.project_name}-${var.environment}-document-ingestion"
  role_arn = module.step_functions_iam.arn

  definition = templatefile("${path.module}/modules/ingestion_pipeline/statemachine/document_ingestion.asl.json", {
    IngestionLambdaArn = module.ingestion_lambda.arn
    IngestionDLQUrl    = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${module.ingestion_dlq.name}"
  })

  logging_configuration {
    log_destination        = "${module.sfn_logs.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-document-ingestion"
  }
}

# --- EventBridge Rule: Trigger Step Functions on S3 Document Upload ---
resource "aws_cloudwatch_event_rule" "s3_upload" {
  name        = "${var.project_name}-${var.environment}-s3-document-upload"
  description = "Trigger Step Functions ingestion pipeline when documents are uploaded to S3"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [module.documents_bucket.bucket]
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-upload-rule"
  }
}

# EventBridge IAM Role & Policy to execute Step Functions (via modules/iam)
module "eventbridge_sfn_iam" {
  source = "./modules/iam"

  role_name        = "${var.project_name}-${var.environment}-eventbridge-sfn-role"
  role_description = "IAM role for EventBridge to trigger Step Functions document ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })

  policy_name        = "${var.project_name}-${var.environment}-eventbridge-sfn-policy"
  policy_description = "Allow EventBridge to start Step Functions execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "states:StartExecution"
      Effect   = "Allow"
      Resource = aws_sfn_state_machine.ingestion.arn
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eventbridge-sfn-role"
  }
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "StepFunctionsDocumentIngestion"
  arn       = aws_sfn_state_machine.ingestion.arn
  role_arn  = module.eventbridge_sfn_iam.arn
}


# module "ingestion_pipeline" {
#   source                     = "./modules/ingestion_pipeline"
#   project_name               = var.project_name
#   environment                = var.environment
#   vpc_id                     = module.vpc.vpc_id
#   private_subnet_ids         = module.vpc.private_subnet_ids
#   lambda_security_group_id   = module.security.lambda_security_group_id
#   storage_kms_key_arn        = module.security.storage_kms_key_arn
#   compute_kms_key_arn        = module.security.compute_kms_key_arn
#   aurora_secret_arn          = module.aurora_pgvector.secret_arn
#   aurora_cluster_endpoint    = module.aurora_pgvector.cluster_endpoint
#   database_name              = module.aurora_pgvector.database_name
#   bedrock_embedding_model_id = var.bedrock_embedding_model_id
#   chunk_size                 = var.chunk_size
#   chunk_overlap              = var.chunk_overlap
#   embedding_dimension        = var.embedding_dimension
# }

# 8. Query Serving Plane: API Gateway, Query Lambda, Bedrock Claude 3.5 Sonnet
data "archive_file" "query_pkg" {
  type        = "zip"
  source_dir  = "${path.root}/../src"
  output_path = "${path.module}/query_lambda.zip"
}

module "lambda_artifacts_bucket" {
  source = "./modules/s3"

  bucket_name             = "${var.project_name}-${var.environment}-lambda-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy           = true
  versioning_enabled      = "Enabled"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  objects = [
    {
      source = data.archive_file.query_pkg.output_path
      key    = "lambda/query_lambda.zip"
    },
    {
      source = data.archive_file.ingestion_pkg.output_path
      key    = "lambda/ingestion_lambda.zip"
    }
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-artifacts"
  }
}

# --- Query Lambda IAM Role & Policy (via modules/iam) ---
module "query_lambda_iam" {
  source = "./modules/iam"

  role_name        = "${var.project_name}-${var.environment}-query-lambda-role"
  role_description = "IAM role for Enterprise RAG Query Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  policy_name        = "${var.project_name}-${var.environment}-query-lambda-policy"
  policy_description = "Least-privilege permissions for Query Lambda (VPC ENIs, Bedrock, Guardrails, Secrets Manager, KMS, CloudWatch)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaVPCAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockInferenceAndGuardrails"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ApplyGuardrail"
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_embedding_model_id}",
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_llm_model_id}",
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:guardrail/${module.bedrock_guardrails.guardrail_id}"
        ]
      },
      {
        Sid    = "AuroraSecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [module.aurora_pgvector.secret_arn]
      },
      {
        Sid    = "KMSDecryptAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = [
          module.storage_kms.arn,
          module.compute_logs_kms.arn
        ]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-query-lambda-role"
  }
}

# --- Query Lambda Function (via modules/lambda, inside Private Subnets) ---
module "query_lambda" {
  source = "./modules/lambda"

  function_name           = "${var.project_name}-${var.environment}-query-service"
  role_arn                = module.query_lambda_iam.arn
  handler                 = "query.handler.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.lambda_artifacts_bucket.objects[0].bucket
  s3_key                  = module.lambda_artifacts_bucket.objects[0].key
  code_signing_config_arn = null
  layers                  = []
  permissions             = []

  vpc_config = {
    subnet_ids         = toset(module.vpc.private_subnet_ids)
    security_group_ids = toset([module.lambda_sg.id])
  }

  env_variables = {
    ENVIRONMENT                         = var.environment
    AURORA_SECRET_ARN                   = module.aurora_pgvector.secret_arn
    AURORA_CLUSTER_ENDPOINT             = module.aurora_pgvector.cluster_endpoint
    DATABASE_NAME                       = module.aurora_pgvector.database_name
    REDIS_ENDPOINT                      = module.elasticache_redis.endpoint
    REDIS_PORT                          = tostring(module.elasticache_redis.port)
    BEDROCK_EMBEDDING_MODEL_ID          = var.bedrock_embedding_model_id
    BEDROCK_LLM_MODEL_ID                = var.bedrock_llm_model_id
    BEDROCK_GUARDRAIL_ID                = module.bedrock_guardrails.guardrail_id
    BEDROCK_GUARDRAIL_VERSION           = module.bedrock_guardrails.guardrail_version
    SEMANTIC_CACHE_TTL_SECONDS          = tostring(var.semantic_cache_ttl_seconds)
    SEMANTIC_CACHE_SIMILARITY_THRESHOLD = tostring(var.semantic_cache_similarity_threshold)
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-query-service"
  }
}

# --- HTTP API Gateway ---
resource "aws_apigatewayv2_api" "rag_api" {
  name          = "${var.project_name}-${var.environment}-rag-api"
  protocol_type = "HTTP"
  description   = "Serverless API Gateway for Enterprise RAG Query Engine"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Api-Key"]
    max_age       = 3600
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rag-api"
  }
}

# Integration with Query Lambda
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.rag_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.query.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Routes:
# 1. POST /query - Vector search & Bedrock RAG synthesis with semantic cache
resource "aws_apigatewayv2_route" "query" {
  api_id    = aws_apigatewayv2_api.rag_api.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# 2. GET /health - Service health check
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.rag_api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# 3. GET /metrics - Cache stats and RAG latency metrics
resource "aws_apigatewayv2_route" "metrics" {
  api_id    = aws_apigatewayv2_api.rag_api.id
  route_key = "GET /metrics"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# CloudWatch Log Group for API Gateway Access Logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}-api"
  retention_in_days = 90
  kms_key_id        = var.compute_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-api-logs"
  }
}

# Stage with Throttling and Access Logging
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.rag_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
    })
  }

  default_route_settings {
    throttling_burst_limit = 1000
    throttling_rate_limit  = 500
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-prod-stage"
  }
}

# Lambda Permission for API Gateway invocation
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rag_api.execution_arn}/*/*"
}

# module "query_api" {
#   source                              = "./modules/query_api"
#   project_name                        = var.project_name
#   environment                         = var.environment
#   vpc_id                              = module.vpc.vpc_id
#   private_subnet_ids                  = module.vpc.private_subnet_ids
#   lambda_security_group_id            = module.security.lambda_security_group_id
#   storage_kms_key_arn                 = module.security.storage_kms_key_arn
#   compute_kms_key_arn                 = module.security.compute_kms_key_arn
#   aurora_secret_arn                   = module.aurora_pgvector.secret_arn
#   aurora_cluster_endpoint             = module.aurora_pgvector.cluster_endpoint
#   database_name                       = module.aurora_pgvector.database_name
#   redis_endpoint                      = module.elasticache_redis.endpoint
#   redis_port                          = module.elasticache_redis.port
#   bedrock_embedding_model_id          = var.bedrock_embedding_model_id
#   bedrock_llm_model_id                = var.bedrock_llm_model_id
#   guardrail_id                        = module.bedrock_guardrails.guardrail_id
#   guardrail_version                   = module.bedrock_guardrails.guardrail_version
#   semantic_cache_ttl_seconds          = var.semantic_cache_ttl_seconds
#   semantic_cache_similarity_threshold = var.semantic_cache_similarity_threshold
# }

# 9. Observability & Monitoring: CloudWatch Dashboard & Alarms
# module "monitoring" {
#   source             = "./modules/monitoring"
#   project_name       = var.project_name
#   environment        = var.environment
#   ingestion_dlq_name = split(":", module.ingestion_pipeline.ingestion_dlq_arn)[5]
#   query_lambda_name  = module.query_api.query_lambda_name
#   step_function_arn  = module.ingestion_pipeline.step_function_arn
# }

# --- CloudWatch Metric Alarm: DLQ Messages > 0 ---
module "ingestion_dlq_alarm" {
  source = "./modules/cloudwatch/cloudwatch-alarm"

  alarm_name          = "${var.project_name}-${var.environment}-ingestion-dlq-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Triggered when documents fail ingestion and land in the Ingestion Dead Letter Queue"
  alarm_actions       = []
  ok_actions          = []

  dimensions = {
    QueueName = split(":", module.ingestion_pipeline.ingestion_dlq_arn)[5]
  }
}

# --- CloudWatch Metric Alarm: Query Lambda Errors ---
module "query_errors_alarm" {
  source = "./modules/cloudwatch/cloudwatch-alarm"

  alarm_name          = "${var.project_name}-${var.environment}-query-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggered when Query Lambda encounters consecutive execution errors"
  alarm_actions       = []
  ok_actions          = []

  dimensions = {
    FunctionName = module.query_api.query_lambda_name
  }
}

# --- CloudWatch Operational Dashboard ---
module "rag_dashboard" {
  source = "./modules/cloudwatch/cloudwatch-dashboard"

  dashboard_name = "${var.project_name}-${var.environment}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "CacheHits", "Environment", var.environment, { stat = "Sum", color = "#2ca02c" }],
            ["EnterpriseRAG", "CacheMisses", "Environment", var.environment, { stat = "Sum", color = "#d62728" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Semantic Cache Performance (Hits vs Misses)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "QueryLatencyMs", "Environment", var.environment, { stat = "p95", color = "#ff7f0e" }],
            ["EnterpriseRAG", "CacheLookupLatencyMs", "Environment", var.environment, { stat = "p95", color = "#1f77b4" }],
            ["EnterpriseRAG", "VectorSearchLatencyMs", "Environment", var.environment, { stat = "p95", color = "#9467bd" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "RAG Query Latency Profile (p95 ms)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "GuardrailBlockedInputs", "Environment", var.environment, { stat = "Sum", color = "#e377c2" }],
            ["EnterpriseRAG", "GuardrailBlockedOutputs", "Environment", var.environment, { stat = "Sum", color = "#8c564b" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Bedrock Guardrail Interventions (Prompt Injections & Violations)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", split(":", module.ingestion_pipeline.ingestion_dlq_arn)[5], { stat = "Maximum", color = "#d62728" }]
          ]
          period = 60
          region = data.aws_region.current.name
          title  = "Ingestion DLQ Messages"
          view   = "timeSeries"
        }
      }
    ]
  })
}