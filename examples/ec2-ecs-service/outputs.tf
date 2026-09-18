output "nginx_ec2_service_name" {
  description = "Nginx EC2 ECS service name"
  value       = module.ecs_nginx.ec2_service_name
}

output "apache_ec2_service_name" {
  description = "Apache EC2 ECS service name"
  value       = module.ecs_apache.ec2_service_name
}

output "nginx_ec2_td_arn" {
  description = "Nginx EC2 task definition ARN"
  value       = module.ecs_nginx.ec2_td_arn
}

output "apache_ec2_td_arn" {
  description = "Apache EC2 task definition ARN"
  value       = module.ecs_apache.ec2_td_arn
}
