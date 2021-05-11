output "consul_server_lb_address" {
  value = "http://${module.consul_server.lb_dns_name}:8500"
}

output "mesh_client_lb_address" {
  value = "http://${aws_lb.mesh-client.dns_name}:9090/ui"
}
