module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                                   = var.vpc_name != "" ? var.vpc_name : "${var.project_name}-${var.environment}-vpc"
  cidr                                   = var.vpc_cidr
  azs                                    = local.azs
  database_subnets                       = local.database_subnets
  public_subnets                         = local.public_subnets
  private_subnets                        = local.private_subnets
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  enable_dns_hostnames                   = var.enable_dns_hostnames
  enable_dns_support                     = var.enable_dns_support
  create_igw                             = var.create_igw != null ? var.create_igw : var.enable_nat_gateway
  map_public_ip_on_launch                = var.map_public_ip_on_launch
  enable_nat_gateway                     = var.enable_nat_gateway
  single_nat_gateway                     = var.single_nat_gateway
  one_nat_gateway_per_az                 = var.one_nat_gateway_per_az
  tags                                   = var.tags
}
