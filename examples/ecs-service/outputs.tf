output "nginx_service_id" {
  description = "Nginx ECS service ID"
  value       = module.ecs_nginx.ec2_service_id
}

output "nginx_service_name" {
  description = "Nginx ECS service name"
  value       = module.ecs_nginx.ec2_service_name
}

output "nginx_td_arn" {
  description = "Nginx task definition ARN"
  value       = module.ecs_nginx.ec2_td_arn
}

output "nginx_td_revision" {
  description = "Nginx task definition revision"
  value       = module.ecs_nginx.ec2_td_revision
}

output "apache_service_id" {
  description = "Apache ECS service ID"
  value       = module.ecs_apache.ec2_service_id
}

output "apache_service_name" {
  description = "Apache ECS service name"
  value       = module.ecs_apache.ec2_service_name
}

output "apache_td_arn" {
  description = "Apache task definition ARN"
  value       = module.ecs_apache.ec2_td_arn
}

output "apache_td_revision" {
  description = "Apache task definition revision"
  value       = module.ecs_apache.ec2_td_revision
}

output "task_exec_role_arn" {
  description = "Task execution IAM role ARN"
  value       = module.iam_role_task_exec.arn
}
