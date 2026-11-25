variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ingestion_dlq_name" {
  type = string
}

variable "query_lambda_name" {
  type = string
}

variable "step_function_arn" {
  type = string
}
