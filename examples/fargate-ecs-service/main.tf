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
## Remote state — reads outputs from fargate cluster deployment.
## Replace cluster_name with actual fargate cluster name.
##---------------------------------------------------------------------------------------------------------------------------
data "aws_ecs_cluster" "main" {
  cluster_name = "fargate-test-cluster"
}

data "aws_vpc" "main" {
  tags = {
    Name = "vpc-test"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Type = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Type = "public"
  }
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — nginx secrets
##---------------------------------------------------------------------------------------------------------------------------
module "secret_nginx" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "nginx-fargate"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name        = "ecs/nginx-fargate/db-password"
      description = "Database password for nginx fargate service"
      secret_key_value = {
        DB_PASSWORD = "change-me-nginx-db-pass"
      }
      recovery_window_in_days = 7
    },
    {
      name        = "ecs/nginx-fargate/api-key"
      description = "API key for nginx fargate service"
      secret_key_value = {
        API_KEY = "change-me-nginx-api-key"
      }
      recovery_window_in_days = 7
    }
  ]
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — apache secrets
##---------------------------------------------------------------------------------------------------------------------------
module "secret_apache" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "apache-fargate"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name        = "ecs/apache-fargate/db-password"
      description = "Database password for apache fargate service"
      secret_key_value = {
        DB_PASSWORD = "change-me-apache-db-pass"
      }
      recovery_window_in_days = 7
    },
    {
      name        = "ecs/apache-fargate/api-key"
      description = "API key for apache fargate service"
      secret_key_value = {
        API_KEY = "change-me-apache-api-key"
      }
      recovery_window_in_days = 7
    }
  ]
}

##---------------------------------------------------------------------------------------------------------------------------
## IAM Role — Task execution role (Fargate requires this for pulling images + secrets)
##---------------------------------------------------------------------------------------------------------------------------
module "iam_role_task_exec" {
  source  = "clouddrove/iam-role/aws"
  version = "1.4.0"

  name               = "ecs-fargate-task-exec"
  environment        = local.environment
  label_order        = local.label_order
  enabled            = true
  assume_role_policy = data.aws_iam_policy_document.task_exec_assume.json
  policy_enabled     = true
  policy_arn         = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_exec_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

##---------------------------------------------------------------------------------------------------------------------------
## Security Group — for Fargate ECS services (awsvpc mode needs its own SG)
##---------------------------------------------------------------------------------------------------------------------------
module "sg_service" {
  source  = "clouddrove/security-group/aws"
  version = "2.0.3"

  name        = "ecs-fargate-service"
  environment = local.environment
  label_order = local.label_order
  vpc_id      = data.aws_vpc.main.id

  new_sg_ingress_rules = [
    {
      key                          = "http"
      ip_protocol                  = "tcp"
      from_port                    = 80
      to_port                      = 80
      cidr_ipv4                    = data.aws_vpc.main.cidr_block
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTP from VPC"
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
## ECS Fargate Service — Nginx
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_nginx" {
  source = "../../"

  ## Tags
  name        = "nginx-fargate"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  ## Network
  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.private.ids
  lb_subnet  = data.aws_subnets.public.ids

  lb_security_group = module.sg_service.security_group_id
  https_enabled     = false

  ## ECS Cluster — reference existing fargate cluster, disable cluster creation
  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = data.aws_ecs_cluster.main.cluster_name

  ## Fargate Service
  fargate_service_enabled          = true
  desired_count                    = 1
  assign_public_ip                 = false
  propagate_tags                   = "TASK_DEFINITION"
  scheduling_strategy              = "REPLICA"
  container_name                   = "nginx"
  container_port                   = 80
  target_type                      = "ip"
  weight_simple                    = 1
  weight_spot                      = 1
  base                             = 1
  fargate_capacity_provider_simple = "FARGATE"
  fargate_capacity_provider_spot   = "FARGATE_SPOT"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  ## Task Definition
  fargate_td_enabled       = true
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-nginx.json"
  container_log_group_name = "nginx-fargate-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn             = module.iam_role_task_exec.arn
  execution_role_name            = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_nginx, module.iam_role_task_exec]
}

##---------------------------------------------------------------------------------------------------------------------------
## ECS Fargate Service — Apache
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_apache" {
  source = "../../"

  ## Tags
  name        = "apache-fargate"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  ## Network
  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.private.ids
  lb_subnet  = data.aws_subnets.public.ids

  lb_security_group = module.sg_service.security_group_id
  https_enabled     = false

  ## ECS Cluster — reference existing fargate cluster, disable cluster creation
  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = data.aws_ecs_cluster.main.cluster_name

  ## Fargate Service
  fargate_service_enabled          = true
  desired_count                    = 1
  assign_public_ip                 = false
  propagate_tags                   = "TASK_DEFINITION"
  scheduling_strategy              = "REPLICA"
  container_name                   = "apache"
  container_port                   = 80
  target_type                      = "ip"
  weight_simple                    = 1
  weight_spot                      = 1
  base                             = 1
  fargate_capacity_provider_simple = "FARGATE"
  fargate_capacity_provider_spot   = "FARGATE_SPOT"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  ## Task Definition
  fargate_td_enabled       = true
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-apache.json"
  container_log_group_name = "apache-fargate-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn             = module.iam_role_task_exec.arn
  execution_role_name            = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_apache, module.iam_role_task_exec]
}
