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
## Remote state — reads VPC/subnet/cluster outputs from ecs-cluster example
##---------------------------------------------------------------------------------------------------------------------------
data "terraform_remote_state" "ecs_cluster" {
  backend = "local"
  config = {
    path = "../ecs-cluster/terraform.tfstate"
  }
}

locals {
  vpc_id             = data.terraform_remote_state.ecs_cluster.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.ecs_cluster.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.ecs_cluster.outputs.public_subnet_ids
  cluster_name       = data.terraform_remote_state.ecs_cluster.outputs.ec2_cluster_name
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — nginx
##---------------------------------------------------------------------------------------------------------------------------
module "secret_nginx" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "nginx"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name                    = "ecs/nginx/db-password"
      description             = "Database password for nginx service"
      secret_key_value        = { DB_PASSWORD = "change-me-nginx-db-pass" }
      recovery_window_in_days = 7
    },
    {
      name                    = "ecs/nginx/api-key"
      description             = "API key for nginx service"
      secret_key_value        = { API_KEY = "change-me-nginx-api-key" }
      recovery_window_in_days = 7
    }
  ]
}

data "aws_secretsmanager_secret" "nginx_db_password" {
  name       = "ecs/nginx/db-password"
  depends_on = [module.secret_nginx]
}

data "aws_secretsmanager_secret" "nginx_api_key" {
  name       = "ecs/nginx/api-key"
  depends_on = [module.secret_nginx]
}

##---------------------------------------------------------------------------------------------------------------------------
## Secrets Manager — apache
##---------------------------------------------------------------------------------------------------------------------------
module "secret_apache" {
  source  = "clouddrove/secrets-manager/aws"
  version = "1.3.0"

  name        = "apache"
  environment = local.environment
  label_order = local.label_order

  secrets = [
    {
      name                    = "ecs/apache/db-password"
      description             = "Database password for apache service"
      secret_key_value        = { DB_PASSWORD = "change-me-apache-db-pass" }
      recovery_window_in_days = 7
    },
    {
      name                    = "ecs/apache/api-key"
      description             = "API key for apache service"
      secret_key_value        = { API_KEY = "change-me-apache-api-key" }
      recovery_window_in_days = 7
    }
  ]
}

data "aws_secretsmanager_secret" "apache_db_password" {
  name       = "ecs/apache/db-password"
  depends_on = [module.secret_apache]
}

data "aws_secretsmanager_secret" "apache_api_key" {
  name       = "ecs/apache/api-key"
  depends_on = [module.secret_apache]
}

##---------------------------------------------------------------------------------------------------------------------------
## IAM Role — shared task execution role
##---------------------------------------------------------------------------------------------------------------------------
module "iam_role_task_exec" {
  source  = "clouddrove/iam-role/aws"
  version = "1.4.0"

  name               = "ecs-task-exec"
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
## Security Group — for ECS services
##---------------------------------------------------------------------------------------------------------------------------
module "sg_service" {
  source  = "clouddrove/security-group/aws"
  version = "2.0.3"

  name        = "ecs-service"
  environment = local.environment
  label_order = local.label_order
  vpc_id      = local.vpc_id

  new_sg_ingress_rules = [
    {
      key                          = "http"
      ip_protocol                  = "tcp"
      from_port                    = 80
      to_port                      = 80
      cidr_ipv4                    = local.vpc_id
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTP from VPC"
      tags                         = {}
    },
    {
      key                          = "ephemeral-ports"
      ip_protocol                  = "tcp"
      from_port                    = 32768
      to_port                      = 65535
      cidr_ipv4                    = local.vpc_id
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow ALB health checks on ephemeral ports (EC2 bridge mode)"
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
## Shared ALB — 1 load balancer for both nginx and apache
##---------------------------------------------------------------------------------------------------------------------------
module "alb" {
  source  = "clouddrove/alb/aws"
  version = "2.0.0"

  name                       = "ecs-ec2-alb"
  load_balancer_type         = "application"
  enable                     = true
  internal                   = false
  enable_deletion_protection = false
  https_enabled              = false
  http_enabled               = true
  http_listener_type         = "forward"
  subnets                    = local.public_subnet_ids
  target_id                  = []
  vpc_id                     = local.vpc_id
  https_port                 = 443
  listener_type              = "forward"
  target_group_port          = 80
  with_target_group          = true

  ## ALB SG — allow HTTP inbound
  enable_security_group = true
  allowed_ip            = ["0.0.0.0/0"]
  allowed_ports         = [80]

  target_groups = [
    {
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "instance"
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
  name        = "ecs-ec2-apache-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

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
## ECS Service — Nginx (uses shared ALB default target group)
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_nginx" {
  source = "../../"

  name        = "nginx"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids
  lb_subnet  = local.public_subnet_ids

  lb_security_group = module.alb.security_group_id
  https_enabled     = false

  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = local.cluster_name

  ec2_service_enabled                = true
  desired_count                      = 1
  propagate_tags                     = "TASK_DEFINITION"
  scheduling_strategy                = "REPLICA"
  container_name                     = "nginx"
  container_port                     = 80
  target_type                        = "instance"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  ## Shared ALB — skip internal ALB creation
  create_alb       = false
  target_group_arn = module.alb.main_target_group_arn

  ec2_td_enabled           = true
  network_mode             = "bridge"
  ipc_mode                 = "task"
  pid_mode                 = "task"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-nginx.tftpl"
  template_vars = {
    db_password_arn = data.aws_secretsmanager_secret.nginx_db_password.arn
    api_key_arn     = data.aws_secretsmanager_secret.nginx_api_key.arn
  }
  container_log_group_name = "nginx-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn       = module.iam_role_task_exec.arn
  execution_role_name      = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_nginx, module.iam_role_task_exec, module.alb]
}

##---------------------------------------------------------------------------------------------------------------------------
## ECS Service — Apache (uses shared ALB apache target group)
##---------------------------------------------------------------------------------------------------------------------------
module "ecs_apache" {
  source = "../../"

  name        = "apache"
  repository  = "https://github.com/clouddrove/terraform-aws-ecs"
  environment = local.environment
  label_order = local.label_order
  enabled     = true

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids
  lb_subnet  = local.public_subnet_ids

  lb_security_group = module.alb.security_group_id
  https_enabled     = false

  ec2_cluster_enabled     = false
  fargate_cluster_enabled = false
  ec2_cluster_name        = local.cluster_name

  ec2_service_enabled                = true
  desired_count                      = 1
  propagate_tags                     = "TASK_DEFINITION"
  scheduling_strategy                = "REPLICA"
  container_name                     = "apache"
  container_port                     = 80
  target_type                        = "instance"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  ## Shared ALB — skip internal ALB creation
  create_alb       = false
  target_group_arn = aws_lb_target_group.apache.arn

  ec2_td_enabled           = true
  network_mode             = "bridge"
  ipc_mode                 = "task"
  pid_mode                 = "task"
  cpu                      = 512
  memory                   = 1024
  file_name                = "./td-apache.tftpl"
  template_vars = {
    db_password_arn = data.aws_secretsmanager_secret.apache_db_password.arn
    api_key_arn     = data.aws_secretsmanager_secret.apache_api_key.arn
  }
  container_log_group_name = "apache-container-logs"
  task_role_arn            = module.iam_role_task_exec.arn
  execution_role_arn       = module.iam_role_task_exec.arn
  execution_role_name      = module.iam_role_task_exec.name
  secrets_manager_policy_enabled = true
  retention_in_days        = 30

  depends_on = [module.secret_apache, module.iam_role_task_exec, aws_lb_target_group.apache]
}
