output "cluster_endpoint" {
  value = aws_rds_cluster.postgresql.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.postgresql.reader_endpoint
}

output "cluster_identifier" {
  value = aws_rds_cluster.postgresql.cluster_identifier
}

output "database_name" {
  value = var.database_name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}

output "port" {
  value = 5432
}
