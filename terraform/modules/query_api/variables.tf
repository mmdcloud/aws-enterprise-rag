variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "storage_kms_key_arn" {
  type = string
}

variable "compute_kms_key_arn" {
  type = string
}

variable "aurora_secret_arn" {
  type = string
}

variable "aurora_cluster_endpoint" {
  type = string
}

variable "database_name" {
  type = string
}

variable "redis_endpoint" {
  type = string
}

variable "redis_port" {
  type = number
}

variable "bedrock_embedding_model_id" {
  type = string
}

variable "bedrock_llm_model_id" {
  type = string
}

variable "guardrail_id" {
  type = string
}

variable "guardrail_version" {
  type = string
}

variable "semantic_cache_ttl_seconds" {
  type    = number
  default = 86400
}

variable "semantic_cache_similarity_threshold" {
  type    = number
  default = 0.92
}
