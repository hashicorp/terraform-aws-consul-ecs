output "consul_server_url" {
  description = "URL to the Consul dev server."
  value       = "http://${module.consul_server.lb_dns_name}:8500"
}
