output "ecs_service_name" {
  description = "Name of created Consul server ECS service."
  value       = aws_ecs_service.this.name
}

output "lb_dns_name" {
  description = "DNS name of load balancer in front of Consul server."
  value       = var.lb_enabled ? aws_lb.this[0].dns_name : null
}

output "lb_security_group_id" {
  description = "Security group ID of load balancer in front of Consul server."
  value       = var.lb_enabled ? aws_security_group.load_balancer[0].id : null
}

output "ca_cert_arn" {
  value = var.tls ? aws_secretsmanager_secret.ca_cert[0].arn : null
}

output "ca_key_arn" {
  value = var.tls ? aws_secretsmanager_secret.ca_key[0].arn : null
}
