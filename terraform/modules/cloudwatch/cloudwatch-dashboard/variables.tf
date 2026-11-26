variable "dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  type        = string
}

variable "dashboard_body" {
  description = "The JSON body describing the CloudWatch dashboard widgets"
  type        = string
}
