output "api_endpoint" {
  value       = aws_apigatewayv2_api.rag_api.api_endpoint
  description = "Base URL of the RAG Query API Gateway"
}

output "query_lambda_arn" {
  value = aws_lambda_function.query.arn
}

output "query_lambda_name" {
  value = aws_lambda_function.query.function_name
}
