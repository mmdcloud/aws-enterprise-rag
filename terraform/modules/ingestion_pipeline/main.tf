data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --- S3 Document Storage Bucket ---
resource "aws_s3_bucket" "documents" {
  bucket        = "${var.project_name}-${var.environment}-documents-${random_id.bucket_suffix.hex}"
  force_destroy = false

  tags = {
    Name = "${var.project_name}-${var.environment}-documents"
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.storage_kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce TLS and KMS encryption on bucket
resource "aws_s3_bucket_policy" "documents_strict" {
  bucket = aws_s3_bucket.documents.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Enable EventBridge notifications for S3 uploads
resource "aws_s3_bucket_notification" "documents" {
  bucket      = aws_s3_bucket.documents.id
  eventbridge = true
}

# --- Dead Letter Queue (DLQ) for Ingestion Pipeline ---
resource "aws_sqs_queue" "ingestion_dlq" {
  name                      = "${var.project_name}-${var.environment}-ingestion-dlq"
  kms_master_key_id         = var.compute_kms_key_arn
  message_retention_seconds = 1209600 # 14 days

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

# --- Ingestion Lambda IAM Role ---
resource "aws_iam_role" "ingestion_lambda" {
  name = "${var.project_name}-${var.environment}-ingestion-lambda-role"

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
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.ingestion_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ingestion_lambda_permissions" {
  name = "${var.project_name}-${var.environment}-ingestion-permissions"
  role = aws_iam_role.ingestion_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DocumentReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
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
        Resource = [var.aurora_secret_arn]
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
          var.storage_kms_key_arn,
          var.compute_kms_key_arn
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
}

# --- Ingestion Lambda Function ---
resource "aws_lambda_function" "ingestion" {
  filename         = data.archive_file.ingestion_pkg.output_path
  function_name    = "${var.project_name}-${var.environment}-ingestion-worker"
  role             = aws_iam_role.ingestion_lambda.arn
  handler          = "ingestion.handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 1024
  source_code_hash = data.archive_file.ingestion_pkg.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      AURORA_SECRET_ARN          = var.aurora_secret_arn
      AURORA_CLUSTER_ENDPOINT    = var.aurora_cluster_endpoint
      DATABASE_NAME              = var.database_name
      BEDROCK_EMBEDDING_MODEL_ID = var.bedrock_embedding_model_id
      CHUNK_SIZE                 = tostring(var.chunk_size)
      CHUNK_OVERLAP              = tostring(var.chunk_overlap)
      EMBEDDING_DIMENSION        = tostring(var.embedding_dimension)
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ingestion-worker"
  }
}

# --- Step Functions IAM Role ---
resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-${var.environment}-sfn-role"

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
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${var.project_name}-${var.environment}-sfn-policy"
  role = aws_iam_role.step_functions.id

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
          aws_lambda_function.ingestion.arn,
          "${aws_lambda_function.ingestion.arn}:*"
        ]
      },
      {
        Sid    = "SQSSendMessageToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [aws_sqs_queue.ingestion_dlq.arn]
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
}

# --- CloudWatch Log Group for Step Functions ---
resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/vendedlogs/states/${var.project_name}-${var.environment}-ingestion"
  retention_in_days = 90
  kms_key_id        = var.compute_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-sfn-logs"
  }
}

# --- Step Functions State Machine ---
resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.project_name}-${var.environment}-document-ingestion"
  role_arn = aws_iam_role.step_functions.arn

  definition = templatefile("${path.module}/statemachine/document_ingestion.asl.json", {
    IngestionLambdaArn = aws_lambda_function.ingestion.arn
    IngestionDLQUrl    = aws_sqs_queue.ingestion_dlq.url
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
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
        name = [aws_s3_bucket.documents.id]
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-upload-rule"
  }
}

# EventBridge IAM Role to execute Step Functions
resource "aws_iam_role" "eventbridge_sfn" {
  name = "${var.project_name}-${var.environment}-eventbridge-sfn-role"

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
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "${var.project_name}-${var.environment}-eventbridge-sfn-policy"
  role = aws_iam_role.eventbridge_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "states:StartExecution"
      Effect   = "Allow"
      Resource = aws_sfn_state_machine.ingestion.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "StepFunctionsDocumentIngestion"
  arn       = aws_sfn_state_machine.ingestion.arn
  role_arn  = aws_iam_role.eventbridge_sfn.arn
}
