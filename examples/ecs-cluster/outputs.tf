output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.subnets.private_subnet_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.subnets.public_subnet_id
}

output "keypair_name" {
  description = "EC2 key pair name"
  value       = module.ecs_cluster.ssh_key_name
}

output "iam_role_arn" {
  description = "ECS instance IAM role ARN"
  value       = module.iam_role_ecs_instance.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for EBS encryption"
  value       = module.kms_key.key_arn
}

output "ec2_cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs_cluster.ec2_cluster_id
}

output "ec2_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.ec2_cluster_name
}

output "ec2_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.ec2_cluster_arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = module.ecs_cluster.autoscaling_group_name
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}
