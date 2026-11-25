data "aws_region" "current" {}

locals {
  interface_services = {
    bedrock_runtime = "bedrock-runtime"
    bedrock         = "bedrock"
    secretsmanager  = "secretsmanager"
    comprehend      = "comprehend"
    logs            = "logs"
    monitoring      = "monitoring"
    states          = "states"
    sqs             = "sqs"
    kms             = "kms"
  }
}

# --- AWS PrivateLink Interface Endpoints ---
resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_services
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-${each.key}"
  }
}

# --- S3 Gateway Endpoint (Zero Cost, High Throughput) ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.private_route_table_id]

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-s3-gateway"
  }
}
