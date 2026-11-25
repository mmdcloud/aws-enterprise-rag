output "endpoint" {
  value       = aws_elasticache_serverless_cache.redis.endpoint[0].address
  description = "Serverless Redis cache endpoint address"
}

output "port" {
  value       = aws_elasticache_serverless_cache.redis.endpoint[0].port
  description = "Serverless Redis cache port (TLS enabled 6379)"
}

output "arn" {
  value = aws_elasticache_serverless_cache.redis.arn
}
