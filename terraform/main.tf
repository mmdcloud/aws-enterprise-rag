# ==============================================================================
# AWS Enterprise RAG: Production Infrastructure Architecture
# ==============================================================================

# 1. Security & Encryption Subsystem (KMS CMKs, Least-Privilege Security Groups)
module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
}

# 2. VPC Network Subsystem (Multi-AZ, Isolated Database Tier, VPC Flow Logs)
module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway
  kms_key_arn        = module.security.compute_kms_key_arn
}

# 3. VPC Endpoints (AWS PrivateLink: Zero Public Internet Exposure)
module "vpc_endpoints" {
  source                          = "./modules/vpc_endpoints"
  project_name                    = var.project_name
  environment                     = var.environment
  vpc_id                          = module.vpc.vpc_id
  private_subnet_ids              = module.vpc.private_subnet_ids
  private_route_table_id          = module.vpc.private_route_table_id
  vpc_endpoints_security_group_id = module.security.vpc_endpoints_security_group_id
}

# 4. Storage & Retrieval Subsystem: Aurora PostgreSQL pgvector
module "aurora_pgvector" {
  source                   = "./modules/aurora_pgvector"
  project_name             = var.project_name
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  database_subnet_ids      = module.vpc.database_subnet_ids
  aurora_security_group_id = module.security.aurora_security_group_id
  kms_key_arn              = module.security.storage_kms_key_arn
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
  redis_security_group_id = module.security.elasticache_security_group_id
  kms_key_arn             = module.security.storage_kms_key_arn
}

# 6. Security & Governance: Bedrock Guardrails (Prompt Injection & Topic Defense)
module "bedrock_guardrails" {
  source       = "./modules/bedrock_guardrails"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.security.compute_kms_key_arn
}

# 7. Ingestion Plane: S3, EventBridge, SQS DLQ, Step Functions, Titan Embeddings v2
module "ingestion_pipeline" {
  source                     = "./modules/ingestion_pipeline"
  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  lambda_security_group_id   = module.security.lambda_security_group_id
  storage_kms_key_arn        = module.security.storage_kms_key_arn
  compute_kms_key_arn        = module.security.compute_kms_key_arn
  aurora_secret_arn          = module.aurora_pgvector.secret_arn
  aurora_cluster_endpoint    = module.aurora_pgvector.cluster_endpoint
  database_name              = module.aurora_pgvector.database_name
  bedrock_embedding_model_id = var.bedrock_embedding_model_id
  chunk_size                 = var.chunk_size
  chunk_overlap              = var.chunk_overlap
  embedding_dimension        = var.embedding_dimension
}

# 8. Query Serving Plane: API Gateway, Query Lambda, Bedrock Claude 3.5 Sonnet
module "query_api" {
  source                              = "./modules/query_api"
  project_name                        = var.project_name
  environment                         = var.environment
  vpc_id                              = module.vpc.vpc_id
  private_subnet_ids                  = module.vpc.private_subnet_ids
  lambda_security_group_id            = module.security.lambda_security_group_id
  storage_kms_key_arn                 = module.security.storage_kms_key_arn
  compute_kms_key_arn                 = module.security.compute_kms_key_arn
  aurora_secret_arn                   = module.aurora_pgvector.secret_arn
  aurora_cluster_endpoint             = module.aurora_pgvector.cluster_endpoint
  database_name                       = module.aurora_pgvector.database_name
  redis_endpoint                      = module.elasticache_redis.endpoint
  redis_port                          = module.elasticache_redis.port
  bedrock_embedding_model_id          = var.bedrock_embedding_model_id
  bedrock_llm_model_id                = var.bedrock_llm_model_id
  guardrail_id                        = module.bedrock_guardrails.guardrail_id
  guardrail_version                   = module.bedrock_guardrails.guardrail_version
  semantic_cache_ttl_seconds          = var.semantic_cache_ttl_seconds
  semantic_cache_similarity_threshold = var.semantic_cache_similarity_threshold
}

# 9. Observability & Monitoring: CloudWatch Dashboard & Alarms
module "monitoring" {
  source             = "./modules/monitoring"
  project_name       = var.project_name
  environment        = var.environment
  ingestion_dlq_name = split(":", module.ingestion_pipeline.ingestion_dlq_arn)[5]
  query_lambda_name  = module.query_api.query_lambda_name
  step_function_arn  = module.ingestion_pipeline.step_function_arn
}
