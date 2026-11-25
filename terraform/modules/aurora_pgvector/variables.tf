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

variable "aurora_security_group_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "database_name" {
  type    = string
  default = "enterpriserag"
}

variable "min_capacity" {
  type    = number
  default = 0.5
}

variable "max_capacity" {
  type    = number
  default = 4.0
}
