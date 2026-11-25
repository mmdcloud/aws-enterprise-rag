output "api_gateway_endpoint" {
  description = "Production RAG Query API Gateway base URL"
  value       = module.query_api.api_endpoint
}

output "document_upload_s3_bucket" {
  description = "S3 bucket for uploading enterprise documents to trigger ingestion"
  value       = module.ingestion_pipeline.document_bucket_name
}

output "step_function_arn" {
  description = "Step Functions State Machine ARN orchestrating the ingestion pipeline"
  value       = module.ingestion_pipeline.step_function_arn
}

output "ingestion_dlq_url" {
  description = "Dead Letter Queue URL for failed ingestion documents"
  value       = module.ingestion_pipeline.ingestion_dlq_url
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
  value       = module.monitoring.dashboard_name
}
