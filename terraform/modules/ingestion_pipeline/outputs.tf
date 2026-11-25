output "document_bucket_name" {
  value = aws_s3_bucket.documents.id
}

output "document_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}

output "step_function_arn" {
  value = aws_sfn_state_machine.ingestion.arn
}

output "ingestion_dlq_url" {
  value = aws_sqs_queue.ingestion_dlq.url
}

output "ingestion_dlq_arn" {
  value = aws_sqs_queue.ingestion_dlq.arn
}

output "ingestion_lambda_arn" {
  value = aws_lambda_function.ingestion.arn
}
