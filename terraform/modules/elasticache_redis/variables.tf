variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "redis_security_group_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "max_cache_storage_gb" {
  type        = number
  default     = 5
  description = "Maximum data storage limit in GB for serverless Redis"
}
