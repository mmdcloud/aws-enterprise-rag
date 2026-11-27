variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "ent-rag"
}

variable "public_subnets" {
  type        = list(string)
  description = "Public Subnet CIDR values"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
}

variable "database_subnets" {
  type        = list(string)
  description = "Database Subnet CIDR values"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Whether to provision NAT Gateways. Set false for pure VPC Endpoint (air-gapped/PrivateLink) mode"
  type        = bool
  default     = false
}

variable "aurora_min_capacity" {
  description = "Minimum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 4.0
}

variable "database_name" {
  description = "Database name for Aurora PostgreSQL"
  type        = string
  default     = "enterpriserag"
}

variable "bedrock_embedding_model_id" {
  description = "Bedrock model ID for text embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "bedrock_llm_model_id" {
  description = "Bedrock model ID for text generation/RAG synthesis"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "semantic_cache_ttl_seconds" {
  description = "TTL in seconds for cached semantic query responses in Redis"
  type        = number
  default     = 86400 # 24 hours
}

variable "semantic_cache_similarity_threshold" {
  description = "Cosine similarity threshold (0.0 to 1.0) to qualify as a semantic cache HIT"
  type        = number
  default     = 0.92
}

variable "chunk_size" {
  description = "Target chunk size in tokens/characters for document chunking"
  type        = number
  default     = 1000
}

variable "chunk_overlap" {
  description = "Overlap size in tokens/characters between consecutive chunks"
  type        = number
  default     = 200
}

variable "embedding_dimension" {
  description = "Dimension of embeddings produced by Titan Text v2 (256, 512, or 1024)"
  type        = number
  default     = 1024
}
