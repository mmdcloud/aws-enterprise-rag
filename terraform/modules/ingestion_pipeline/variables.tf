variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "storage_kms_key_arn" {
  type = string
}

variable "compute_kms_key_arn" {
  type = string
}

variable "aurora_secret_arn" {
  type = string
}

variable "aurora_cluster_endpoint" {
  type = string
}

variable "database_name" {
  type = string
}

variable "bedrock_embedding_model_id" {
  type    = string
  default = "amazon.titan-embed-text-v2:0"
}

variable "chunk_size" {
  type    = number
  default = 1000
}

variable "chunk_overlap" {
  type    = number
  default = 200
}

variable "embedding_dimension" {
  type    = number
  default = 1024
}
