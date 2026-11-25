variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "enable_nat_gateway" {
  type        = bool
  default     = false
  description = "Deploy NAT gateway if external egress is permitted; set false for zero public internet exposure"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for VPC Flow Logs encryption"
}
