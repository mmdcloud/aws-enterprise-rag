output "api_gateway_endpoint" {
  description = "Production RAG Query API Gateway base URL"
  value       = aws_apigatewayv2_api.rag_api.api_endpoint
}

output "document_upload_s3_bucket" {
  description = "S3 bucket for uploading enterprise documents to trigger ingestion"
  value       = module.documents_bucket.bucket
}

output "step_function_arn" {
  description = "Step Functions State Machine ARN orchestrating the ingestion pipeline"
  value       = aws_sfn_state_machine.ingestion.arn
}

output "ingestion_dlq_url" {
  description = "Dead Letter Queue URL for failed ingestion documents"
  value       = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${module.ingestion_dlq.name}"
}

output "aurora_cluster_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint (internal VPC only)"
  value       = module.aurora_pgvector.cluster_endpoint
}

output "redis_cache_endpoint" {
  description = "ElastiCache Serverless Redis endpoint (internal VPC only)"
  value       = module.elasticache_redis.endpoint
}

output "bedrock_guardrail_id" {
  description = "Bedrock Guardrail ID protecting against prompt injections"
  value       = module.bedrock_guardrails.guardrail_id
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch operational dashboard"
  value       = module.rag_dashboard.dashboard_name
}
