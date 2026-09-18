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
## Remote state — reads outputs from fargate cluster deployment
##---------------------------------------------------------------------------------------------------------------------------
data "aws_ecs_cluster" "main" {
  cluster_name = "fargate-test-cluster"
}

data "aws_vpc" "main" {
  tags = { Name = "vpc-test" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = { Type = "private" }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = { Type = "public" }
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — nginx
##---------------------------------------------------------------------------------------------------------------------------
module "secret_nginx" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "nginx-fargate"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name                    = "ecs/nginx-fargate/db-password"
      description             = "Database password for nginx fargate service"
      secret_key_value        = { DB_PASSWORD = "change-me-nginx-db-pass" }
      recovery_window_in_days = 7
    },
    {
      name                    = "ecs/nginx-fargate/api-key"
      description             = "API key for nginx fargate service"
      secret_key_value        = { API_KEY = "change-me-nginx-api-key" }
      recovery_window_in_days = 7
    }
  ]
}

data "aws_secretsmanager_secret" "nginx_db_password" {
  name       = "ecs/nginx-fargate/db-password"
  depends_on = [module.secret_nginx]
}

data "aws_secretsmanager_secret" "nginx_api_key" {
  name       = "ecs/nginx-fargate/api-key"
  depends_on = [module.secret_nginx]
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — apache
##---------------------------------------------------------------------------------------------------------------------------
module "secret_apache" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "apache-fargate"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name                    = "ecs/apache-fargate/db-password"
      description             = "Database password for apache fargate service"
      secret_key_value        = { DB_PASSWORD = "change-me-apache-db-pass" }
      recovery_window_in_days = 7
    },
    {
      name                    = "ecs/apache-fargate/api-key"
      description             = "API key for apache fargate service"
      secret_key_value        = { API_KEY = "change-me-apache-api-key" }
      recovery_window_in_days = 7
    }
  ]
}

data "aws_secretsmanager_secret" "apache_db_password" {
  name       = "ecs/apache-fargate/db-password"
  depends_on = [module.secret_apache]
}

data "aws_secretsmanager_secret" "apache_api_key" {
  name       = "ecs/apache-fargate/api-key"
  depends_on = [module.secret_apache]
}

##---------------------------------------------------------------------------------------------------------------------------
## IAM Role — shared task execution role
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
## Security Group — for Fargate ECS services
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
## Shared ALB — 1 load balancer for both nginx and apache fargate services
##---------------------------------------------------------------------------------------------------------------------------
module "alb" {
  source  = "clouddrove/alb/aws"
  version = "2.0.0"

  name                       = "ecs-fargate-alb"
  load_balancer_type         = "application"
  enable                     = true
  internal                   = true
  enable_deletion_protection = false
  https_enabled              = false
  http_enabled               = true
  http_listener_type         = "forward"
  subnets                    = data.aws_subnets.public.ids
  target_id                  = []
  vpc_id                     = data.aws_vpc.main.id
  https_port                 = 443
  listener_type              = "forward"
  target_group_port          = 80
  with_target_group          = true

  # Default target group — nginx
  target_groups = [
    {
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200-399"
      }
    }
  ]
}

## Separate target group for apache
resource "aws_lb_target_group" "apache" {
  name        = "ecs-fargate-apache-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    protocol            = "HTTP"
    matcher             = "200-399"
  }
}

## Path-based listener rule — /apache* → apache target group
resource "aws_lb_listener_rule" "apache" {
  listener_arn = module.alb.http_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apache.arn
  }

  condition {
    path_pattern {
      values = ["/apache*"]
    }
  }
}

##---------------------------------------------------------------------------------------------------------------------------
## ECS Fargate Service — Nginx (uses shared ALB default target group)
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_nginx" {
  source = "../../"

  name        = "nginx-fargate"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.private.ids
  lb_subnet  = data.aws_subnets.public.ids

  lb_security_group = module.sg_service.security_group_id
  https_enabled     = false

  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = data.aws_ecs_cluster.main.cluster_name

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

  ## Shared ALB — skip internal ALB creation
  create_alb       = false
  target_group_arn = module.alb.main_target_group_arn

  fargate_td_enabled       = true
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-nginx.tftpl"
  template_vars = {
    db_password_arn = data.aws_secretsmanager_secret.nginx_db_password.arn
    api_key_arn     = data.aws_secretsmanager_secret.nginx_api_key.arn
  }
  container_log_group_name = "nginx-fargate-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn       = module.iam_role_task_exec.arn
  execution_role_name      = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_nginx, module.iam_role_task_exec, module.alb]
}

##---------------------------------------------------------------------------------------------------------------------------
## ECS Fargate Service — Apache (uses shared ALB apache target group)
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_apache" {
  source = "../../"

  name        = "apache-fargate"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.private.ids
  lb_subnet  = data.aws_subnets.public.ids

  lb_security_group = module.sg_service.security_group_id
  https_enabled     = false

  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = data.aws_ecs_cluster.main.cluster_name

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

  ## Shared ALB — skip internal ALB creation
  create_alb       = false
  target_group_arn = aws_lb_target_group.apache.arn

  fargate_td_enabled       = true
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-apache.tftpl"
  template_vars = {
    db_password_arn = data.aws_secretsmanager_secret.apache_db_password.arn
    api_key_arn     = data.aws_secretsmanager_secret.apache_api_key.arn
  }
  container_log_group_name = "apache-fargate-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn       = module.iam_role_task_exec.arn
  execution_role_name      = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_apache, module.iam_role_task_exec, aws_lb_target_group.apache]
}
