output "guardrail_id" {
  value = aws_bedrock_guardrail.rag.guardrail_id
}

output "guardrail_arn" {
  value = aws_bedrock_guardrail.rag.guardrail_arn
}

output "guardrail_version" {
  value = aws_bedrock_guardrail_version.prod.version
}
