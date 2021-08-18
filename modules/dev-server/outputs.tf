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
  description = "The ARN of the CA certificate secret for the Consul server."
  value       = var.tls ? aws_secretsmanager_secret.ca_cert[0].arn : null
}

output "ca_key_arn" {
  description = "The ARN of the CA key secret for the Consul server."
  value       = var.tls ? aws_secretsmanager_secret.ca_key[0].arn : null
}

output "server_dns" {
  description = "The DNS name of the Consul server service in AWS CloudMap."
  value       = "${aws_service_discovery_service.server.name}.${aws_service_discovery_private_dns_namespace.server.name}"
}

output "bootstrap_token_secret_arn" {
  description = "The ARN of the ACL bootstrap token secret."
  value       = var.acls ? aws_secretsmanager_secret.bootstrap_token[0].arn : null
}
