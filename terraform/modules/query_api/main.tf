data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- Query Lambda Deployment Package ---
data "archive_file" "query_pkg" {
  type        = "zip"
  source_dir  = "${path.root}/../src"
  output_path = "${path.module}/query_lambda.zip"
}

# --- Query Lambda IAM Role ---
resource "aws_iam_role" "query_lambda" {
  name = "${var.project_name}-${var.environment}-query-lambda-role"

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

resource "aws_iam_role_policy_attachment" "query_lambda_vpc" {
  role       = aws_iam_role.query_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "query_lambda_permissions" {
  name = "${var.project_name}-${var.environment}-query-lambda-policy"
  role = aws_iam_role.query_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:guardrail/${var.guardrail_id}"
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
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Query Lambda Function (Inside Private Subnets) ---
resource "aws_lambda_function" "query" {
  filename         = data.archive_file.query_pkg.output_path
  function_name    = "${var.project_name}-${var.environment}-query-service"
  role             = aws_iam_role.query_lambda.arn
  handler          = "query.handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 1024
  source_code_hash = data.archive_file.query_pkg.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      ENVIRONMENT                         = var.environment
      AURORA_SECRET_ARN                   = var.aurora_secret_arn
      AURORA_CLUSTER_ENDPOINT             = var.aurora_cluster_endpoint
      DATABASE_NAME                       = var.database_name
      REDIS_ENDPOINT                      = var.redis_endpoint
      REDIS_PORT                          = tostring(var.redis_port)
      BEDROCK_EMBEDDING_MODEL_ID          = var.bedrock_embedding_model_id
      BEDROCK_LLM_MODEL_ID                = var.bedrock_llm_model_id
      BEDROCK_GUARDRAIL_ID                = var.guardrail_id
      BEDROCK_GUARDRAIL_VERSION           = var.guardrail_version
      SEMANTIC_CACHE_TTL_SECONDS          = tostring(var.semantic_cache_ttl_seconds)
      SEMANTIC_CACHE_SIMILARITY_THRESHOLD = tostring(var.semantic_cache_similarity_threshold)
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-query-service"
  }
}

# --- CloudWatch Log Group for Query Lambda ---
resource "aws_cloudwatch_log_group" "query_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.query.function_name}"
  retention_in_days = 90
  kms_key_id        = var.compute_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-query-lambda-logs"
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
