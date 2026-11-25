output "dashboard_name" {
  value = aws_cloudwatch_dashboard.rag_dashboard.dashboard_name
}

output "dlq_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.ingestion_dlq_not_empty.arn
}
