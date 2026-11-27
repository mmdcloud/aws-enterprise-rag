# Example Terraform Variables for AWS Enterprise RAG
aws_region   = "us-east-1"
environment  = "prod"
project_name = "ent-rag"

# Networking
vpc_cidr           = "10.0.0.0/16"
enable_nat_gateway = false # Set false for 100% private VPC endpoints (zero public internet)

public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
database_subnets = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Aurora Serverless v2 PostgreSQL (pgvector)
aurora_min_capacity = 0.5
aurora_max_capacity = 4.0
database_name       = "enterpriserag"

# Bedrock Foundation Models
bedrock_embedding_model_id = "amazon.titan-embed-text-v2:0"
bedrock_llm_model_id       = "anthropic.claude-3-5-sonnet-20241022-v2:0"

# Chunking & Embeddings
chunk_size          = 1000
chunk_overlap       = 200
embedding_dimension = 1024

# Semantic Caching
semantic_cache_ttl_seconds          = 86400 # 24 hours
semantic_cache_similarity_threshold = 0.92  # 92% cosine similarity threshold for cache HIT