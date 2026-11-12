output "gossip_key_arn" {
  value = local.generate_gossip_key ? aws_secretsmanager_secret.gossip_key[0].arn : null
}

output "gossip_key" {
  value     = local.generate_gossip_key ? random_id.gossip_key[0].b64_std : null
  sensitive = true
}

output "bootstrap_token_arn" {
  value = local.generate_bootstrap_token ? aws_secretsmanager_secret.bootstrap_token[0].arn : null
}

output "bootstrap_token" {
  value = local.generate_bootstrap_token ? random_uuid.bootstrap_token[0].result : null
}

output "ca_cert_arn" {
  value = var.tls ? local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CA"].arn : null : null
}

output "ca_key_arn" {
  value = var.tls ? local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CA_KEY"].arn : null : null
}

output "alb_iam_cert_arn" {
  value = var.tls ? local.generate_ca ? aws_iam_server_certificate.alb-cert[0].arn : null : null
}

output "client_cert_arn" {
  value = var.tls ? local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CLIENT_CERT"].arn : null : null
}

output "client_key_arn" {
  value = var.tls ? local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CLIENT_KEY"].arn : null : null
}

output "datadog_apikey_arn" {
  value = var.datadog_apikey == "" ? null : aws_secretsmanager_secret.datadog_apikey[0].arn
}

output "consul_server_security_group_id" {
  value = aws_security_group.ecs_service.id
}

output "cloudwatch_log_group_name" {
  value = aws_cloudwatch_log_group.container-logs.name
}

output "mgmt_alb_arn" {
  value = var.lb_enabled ? aws_lb.this[0].arn : null
}

output "mgmt_alb_dns_name" {
  value = var.lb_enabled ? aws_lb.this[0].dns_name : null
}

output "mgmt_alb_security_group_id" {
  value = var.lb_enabled ? aws_security_group.load_balancer[0].id : null
}
