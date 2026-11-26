data "aws_region" "current" {}

# --- CloudWatch Metric Alarm: DLQ Messages > 0 ---
resource "aws_cloudwatch_metric_alarm" "ingestion_dlq_not_empty" {
  alarm_name          = "${var.project_name}-${var.environment}-ingestion-dlq-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Triggered when documents fail ingestion and land in the Ingestion Dead Letter Queue"

  dimensions = {
    QueueName = var.ingestion_dlq_name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-dlq-alarm"
  }
}

# --- CloudWatch Metric Alarm: Query Lambda Errors ---
resource "aws_cloudwatch_metric_alarm" "query_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-query-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggered when Query Lambda encounters consecutive execution errors"

  dimensions = {
    FunctionName = var.query_lambda_name
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-query-error-alarm"
  }
}

# --- CloudWatch Operational Dashboard ---
resource "aws_cloudwatch_dashboard" "rag_dashboard" {
  dashboard_name = "${var.project_name}-${var.environment}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "CacheHits", "Environment", var.environment, { stat = "Sum", color = "#2ca02c" }],
            ["EnterpriseRAG", "CacheMisses", "Environment", var.environment, { stat = "Sum", color = "#d62728" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Semantic Cache Performance (Hits vs Misses)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "QueryLatencyMs", "Environment", var.environment, { stat = "p95", color = "#ff7f0e" }],
            ["EnterpriseRAG", "CacheLookupLatencyMs", "Environment", var.environment, { stat = "p95", color = "#1f77b4" }],
            ["EnterpriseRAG", "VectorSearchLatencyMs", "Environment", var.environment, { stat = "p95", color = "#9467bd" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "RAG Query Latency Profile (p95 ms)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["EnterpriseRAG", "GuardrailBlockedInputs", "Environment", var.environment, { stat = "Sum", color = "#e377c2" }],
            ["EnterpriseRAG", "GuardrailBlockedOutputs", "Environment", var.environment, { stat = "Sum", color = "#8c564b" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Bedrock Guardrail Interventions (Prompt Injections & Violations)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.ingestion_dlq_name, { stat = "Maximum", color = "#d62728" }]
          ]
          period = 60
          region = data.aws_region.current.name
          title  = "Ingestion DLQ Messages"
          view   = "timeSeries"
        }
      }
    ]
  })
}