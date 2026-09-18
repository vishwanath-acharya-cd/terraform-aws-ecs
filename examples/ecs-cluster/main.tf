##---------------------------------------------------------------------------------------------------------------------------
## Provider block
##---------------------------------------------------------------------------------------------------------------------------
provider "aws" {
  region = "eu-west-1"
}

locals {
  environment = "test"
  label_order = ["name", "environment"]
}

##---------------------------------------------------------------------------------------------------------------------------
## VPC
##---------------------------------------------------------------------------------------------------------------------------
module "vpc" {
  source  = "clouddrove/vpc/aws"
  version = "2.0.5"

  name        = "vpc"
  repository  = "https://github.com/clouddrove/terraform-aws-vpc"
  environment = local.environment
  label_order = local.label_order
  cidr_block  = "10.10.0.0/16"
}

##---------------------------------------------------------------------------------------------------------------------------
## Subnets
##---------------------------------------------------------------------------------------------------------------------------
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

##---------------------------------------------------------------------------------------------------------------------------
## Security Group — SSH access
##---------------------------------------------------------------------------------------------------------------------------
module "sg_ssh" {
  source  = "clouddrove/security-group/aws"
  version = "2.0.3"

  name        = "ssh"
  environment = local.environment
  label_order = local.label_order
  vpc_id      = module.vpc.vpc_id

  new_sg_ingress_rules = [
    {
      key                          = "ssh-vpc"
      ip_protocol                  = "tcp"
      from_port                    = 22
      to_port                      = 22
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow SSH from VPC"
      tags                         = {}
    }
  ]

  new_sg_egress_rules = [
    {
      key                          = "all-ipv4"
      ip_protocol                  = "-1"
      from_port                    = null
      to_port                      = null
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow all outbound"
      tags                         = {}
    }
  ]
}

##---------------------------------------------------------------------------------------------------------------------------
## Security Group — HTTP/HTTPS for LB
##---------------------------------------------------------------------------------------------------------------------------
module "sg_lb" {
  source  = "clouddrove/security-group/aws"
  version = "2.0.3"

  name        = "lb"
  environment = local.environment
  label_order = local.label_order
  vpc_id      = module.vpc.vpc_id

  new_sg_ingress_rules = [
    {
      key                          = "http"
      ip_protocol                  = "tcp"
      from_port                    = 80
      to_port                      = 80
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTP"
      tags                         = {}
    },
    {
      key                          = "https"
      ip_protocol                  = "tcp"
      from_port                    = 443
      to_port                      = 443
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTPS"
      tags                         = {}
    },
    {
      key                          = "ephemeral"
      ip_protocol                  = "tcp"
      from_port                    = 32768
      to_port                      = 65535
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow ALB health checks on ephemeral ports (ECS bridge mode)"
      tags                         = {}
    }
  ]

  new_sg_egress_rules = [
    {
      key                          = "all-ipv4"
      ip_protocol                  = "-1"
      from_port                    = null
      to_port                      = null
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow all outbound"
      tags                         = {}
    }
  ]
}

##---------------------------------------------------------------------------------------------------------------------------
## KMS Key — for EBS encryption
##---------------------------------------------------------------------------------------------------------------------------
module "kms_key" {
  source  = "clouddrove/kms/aws"
  version = "1.3.4"

  name                     = "kms"
  repository               = "https://github.com/clouddrove/terraform-aws-kms"
  environment              = local.environment
  label_order              = local.label_order
  enabled                  = true
  description              = "KMS key for ECS EBS encryption"
  alias                    = "alias/ecs-cluster"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days  = 7
  enable_key_rotation      = true
  policy                   = data.aws_iam_policy_document.kms.json
}

data "aws_iam_policy_document" "kms" {
  version = "2012-10-17"
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

##---------------------------------------------------------------------------------------------------------------------------
## IAM Role — ECS EC2 instance profile (allows EC2 to register with ECS cluster)
##---------------------------------------------------------------------------------------------------------------------------
module "iam_role_ecs_instance" {
  source  = "clouddrove/iam-role/aws"
  version = "1.4.0"

  name               = "ecs-instance"
  environment        = local.environment
  label_order        = local.label_order
  enabled            = true
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  policy_enabled     = true
  policy_arn         = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

##---------------------------------------------------------------------------------------------------------------------------
## ECS Cluster (EC2 launch type with capacity providers)
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_cluster" {
  source = "../../"

  ## Tags
  name        = "ecs-cluster"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true
  https_enabled = false
  ## Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.subnets.private_subnet_id

  additional_security_group_ids = [module.sg_ssh.security_group_id, module.sg_lb.security_group_id]
  lb_security_group             = module.sg_lb.security_group_id
  lb_subnet                     = module.subnets.public_subnet_id
  target_type                   = "instance"

  ## ECS Cluster — EC2 launch type only
  ec2_cluster_enabled  = true
  ecs_settings_enabled = "enabled"
  cloudwatch_prefix    = "ecs-cluster-logs"
  retention_in_days    = 30

  ## Disable built-in autoscaling, service and task definition
  autoscaling_policies_enabled = false
  ec2_service_enabled          = false
  ec2_td_enabled               = false
  autoscaling_group_arn        = module.ec2_autoscaling.autoscaling_group_arn
  capacity_provider_enabled    = true
}

##---------------------------------------------------------------------------------------------------------------------------
## EC2 Auto Scaling — external module
##---------------------------------------------------------------------------------------------------------------------------
module "ec2_autoscaling" {
  source  = "clouddrove/ec2-autoscaling/aws"
  version = "1.5.0"

  ## Tags
  name        = "ecs-cluster"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  ## Launch Template
  image_id                  = "ami-04166c7920d59ea63" # ECS-optimized AMI eu-west-1
  instance_type             = "t3.medium"
  key_name                  = module.ecs_cluster.ssh_key_name
  security_group_ids        = [module.sg_ssh.security_group_id, module.sg_lb.security_group_id]
  iam_instance_profile_name = module.iam_role_ecs_instance.name
  instance_profile_enabled  = true
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${module.ecs_cluster.ec2_cluster_name} >> /etc/ecs/ecs.config
    echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
    echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
  EOF
  )
  ebs_encryption = true
  kms_key_arn    = module.kms_key.key_arn
  volume_size    = 20

  ## ASG
  subnet_ids                  = module.subnets.public_subnet_id
  associate_public_ip_address = true
  min_size          = 1
  max_size          = 3
  desired_capacity  = 1
  health_check_type = "EC2"

  cpu_utilization_low_period_seconds  = 300
  cpu_utilization_high_period_seconds = 300

  ## Scheduled scaling
  schedule_enabled = true
  scheduler_down   = "0 19 * * MON-FRI"
  scheduler_up     = "0 6 * * MON-FRI"
  min_size_scaleup = 1
  max_size_scaleup = 3
  scale_up_desired = 2
}


