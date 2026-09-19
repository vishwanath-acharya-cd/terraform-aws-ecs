provider "aws" {
  region = "eu-west-1"
}

locals {
  environment = "test"
  label_order = ["name", "environment"]
}

module "vpc" {
  source  = "clouddrove/vpc/aws"
  version = "2.0.5"

  name        = "vpc"
  repository  = "https://github.com/clouddrove/terraform-aws-vpc"
  environment = local.environment
  label_order = local.label_order
  cidr_block  = "10.10.0.0/16"
}

module "subnets" {
  source  = "clouddrove/subnet/aws"
  version = "2.0.3"

  name                = "subnets"
  repository          = "https://github.com/clouddrove/terraform-aws-subnet"
  environment         = local.environment
  label_order         = local.label_order
  nat_gateway_enabled = true
  availability_zones  = ["eu-west-1a", "eu-west-1b"]
  vpc_id              = module.vpc.vpc_id
  cidr_block          = module.vpc.vpc_cidr_block
  type                = "public-private"
  igw_id              = module.vpc.igw_id
  ipv6_cidr_block     = module.vpc.ipv6_cidr_block
}

module "fargate_cluster" {
  source = "../../"

  name        = "fargate"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.subnets.private_subnet_id
  lb_subnet  = module.subnets.public_subnet_id

  fargate_cluster_enabled = true
  ecs_settings_enabled    = "enabled"
  fargate_cluster_cp      = ["FARGATE", "FARGATE_SPOT"]

  ## Disable service + task definition — cluster only
  ec2_cluster_enabled = false
  ec2_service_enabled = false
  ec2_td_enabled      = false
  https_enabled       = false
  create_alb          = false
  lb_security_group   = ""
}

output "fargate_cluster_name" {
  value = module.fargate_cluster.fargate_cluster_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.subnets.private_subnet_id
}

output "public_subnet_ids" {
  value = module.subnets.public_subnet_id
}
