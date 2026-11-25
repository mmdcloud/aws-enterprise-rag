# --- Amazon ElastiCache Serverless (Redis) for Semantic Caching ---
resource "aws_elasticache_serverless_cache" "redis" {
  name        = "${var.project_name}-${var.environment}-cache"
  engine      = "redis"
  description = "Production ElastiCache Serverless Redis for RAG Semantic Caching"
  kms_key_id  = var.kms_key_arn
  subnet_ids  = var.database_subnet_ids

  security_group_ids = [var.redis_security_group_id]

  cache_usage_limits {
    data_storage {
      maximum = var.max_cache_storage_gb
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-semantic-cache"
  }
}
