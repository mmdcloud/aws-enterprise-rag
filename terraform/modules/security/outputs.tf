output "storage_kms_key_arn" {
  value = aws_kms_key.storage.arn
}

output "storage_kms_key_id" {
  value = aws_kms_key.storage.key_id
}

output "compute_kms_key_arn" {
  value = aws_kms_key.compute_logs.arn
}

output "compute_kms_key_id" {
  value = aws_kms_key.compute_logs.key_id
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "elasticache_security_group_id" {
  value = aws_security_group.elasticache.id
}

output "vpc_endpoints_security_group_id" {
  value = aws_security_group.vpc_endpoints.id
}
