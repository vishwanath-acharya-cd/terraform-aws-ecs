##-----------------------------------------------------------------------------
## SSH Key — self-generated, private key saved locally (from ecs-cluster example)
##-----------------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  count     = var.ec2_cluster_enabled ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  count      = var.ec2_cluster_enabled ? 1 : 0
  key_name   = "${var.name}-${var.environment}-key"
  public_key = tls_private_key.ssh[0].public_key_openssh
}

resource "local_file" "private_key" {
  count           = var.ec2_cluster_enabled ? 1 : 0
  content         = tls_private_key.ssh[0].private_key_pem
  filename        = "${path.module}/${var.name}-${var.environment}-key.pem"
  file_permission = "0600"
}

##-----------------------------------------------------------------------------
## ECS Capacity Provider — links ASG to ECS cluster (from ecs-cluster example)
##-----------------------------------------------------------------------------
resource "aws_ecs_capacity_provider" "ec2" {
  count = var.ec2_cluster_enabled && var.autoscaling_policies_enabled == false && var.autoscaling_group_arn != "" ? 1 : 0
  name  = "cp-${var.name}-${var.environment}"

  auto_scaling_group_provider {
    auto_scaling_group_arn = var.autoscaling_group_arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 80
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 3
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "ec2" {
  count              = var.ec2_cluster_enabled && var.autoscaling_policies_enabled == false && var.autoscaling_group_arn != "" ? 1 : 0
  cluster_name       = module.ecs.ec2_name
  capacity_providers = [aws_ecs_capacity_provider.ec2[0].name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2[0].name
    weight            = 1
    base              = 1
  }
}

##-----------------------------------------------------------------------------
## IAM Role Policy — Secrets Manager access for task execution (from ecs-service example)
##-----------------------------------------------------------------------------
resource "aws_iam_role_policy" "secrets_access" {
  count = var.secrets_manager_policy_enabled ? 1 : 0
  name  = "${var.name}-${var.environment}-secrets-access"
  role  = var.execution_role_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:*:*:secret:ecs/${var.name}/*"]
      }
    ]
  })
}

##-----------------------------------------------------------------------------
## ecs module call.
##-----------------------------------------------------------------------------
module "ecs" {
  source                  = "./modules/ecs"
  name                    = var.name
  repository              = var.repository
  environment             = var.environment
  managedby               = var.managedby
  delimiter               = var.delimiter
  label_order             = var.label_order
  enabled                 = var.enabled
  ec2_cluster_enabled     = var.ec2_cluster_enabled
  fargate_cluster_enabled = var.fargate_cluster_enabled
  ecs_settings_enabled    = var.ecs_settings_enabled
  fargate_cluster_cp      = var.fargate_cluster_cp
  extra_tags              = var.extra_tags
}

##-----------------------------------------------------------------------------
## service module call.
##-----------------------------------------------------------------------------
module "service" {
  source                             = "./modules/service"
  name                               = var.name
  environment                        = var.environment
  managedby                          = var.managedby
  delimiter                          = var.delimiter
  label_order                        = var.label_order
  enabled                            = var.enabled
  ec2_service_enabled                = var.ec2_service_enabled
  ec2_cluster_name                   = var.ec2_cluster_name != "" ? var.ec2_cluster_name : module.ecs.ec2_id
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  desired_count                      = var.desired_count
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  ec2_awsvpc_enabled                 = var.ec2_awsvpc_enabled
  propagate_tags                     = var.propagate_tags
  scheduling_strategy                = var.scheduling_strategy
  ec2_task_definition                = module.task-definition.ec2_arn
  type                               = var.type
  container_name                     = var.container_name
  container_port                     = var.container_port
  fargate_service_enabled            = var.fargate_service_enabled
  fargate_cluster_name               = module.ecs.fargate_id
  platform_version                   = var.platform_version
  fargate_task_definition            = module.task-definition.fargate_arn
  fargate_capacity_provider_simple   = var.fargate_capacity_provider_simple
  fargate_capacity_provider_spot     = var.fargate_capacity_provider_spot
  weight_simple                      = var.weight_simple
  weight_spot                        = var.weight_spot
  base                               = var.base
  subnets                            = var.subnet_ids
  assign_public_ip                   = var.assign_public_ip
  lb_subnet                          = var.lb_subnet
  vpc_id                             = var.vpc_id
  target_type                        = var.target_type
  network_mode                       = var.network_mode
  listener_certificate_arn           = var.listener_certificate_arn
  https_enabled                      = var.https_enabled
  http_listener_type                 = var.http_listener_type
  extra_tags                         = var.extra_tags
}

##-----------------------------------------------------------------------------
## task-definition module call.
##-----------------------------------------------------------------------------
module "task-definition" {
  source                   = "./modules/task-definition"
  name                     = var.name
  environment              = var.environment
  managedby                = var.managedby
  delimiter                = var.delimiter
  label_order              = var.label_order
  enabled                  = var.enabled
  ec2_td_enabled           = var.ec2_td_enabled
  fargate_td_enabled       = var.fargate_td_enabled
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  file_name                = var.file_name
  container_log_group_name = var.container_log_group_name
  ipc_mode                 = var.ipc_mode
  pid_mode                 = var.pid_mode
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = var.network_mode
  kms_key_arn              = var.kms_key_arn
  retention_in_days        = var.retention_in_days
  extra_tags               = var.extra_tags
}
