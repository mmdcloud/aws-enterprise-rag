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

variable "private_route_table_id" {
  type = string
}

variable "vpc_endpoints_security_group_id" {
  type = string
}
