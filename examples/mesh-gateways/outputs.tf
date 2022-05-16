output "dc1_server_url" {
  value = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
}

output "dc2_server_url" {
  value = "http://${module.dc2.dev_consul_server.lb_dns_name}:8500"
}

output "client_lb_address" {
  value = "http://${aws_lb.example_client_app.dns_name}:9090/ui"
}

output "private_subnets" {
  value = module.dc1_vpc.private_subnets
}
