output "nginx_fargate_service_name" {
  description = "Nginx Fargate ECS service name"
  value       = module.ecs_nginx.fargate_service_name
}

output "apache_fargate_service_name" {
  description = "Apache Fargate ECS service name"
  value       = module.ecs_apache.fargate_service_name
}

output "nginx_fargate_td_arn" {
  description = "Nginx Fargate task definition ARN"
  value       = module.ecs_nginx.fargate_td_arn
}

output "apache_fargate_td_arn" {
  description = "Apache Fargate task definition ARN"
  value       = module.ecs_apache.fargate_td_arn
}
