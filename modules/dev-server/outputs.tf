output "service_name" {
  value = aws_ecs_service.this.name
}

output "lb_dns_name" {
  value = var.load_balancer_enabled ? aws_lb.this[0].dns_name : ""
}
