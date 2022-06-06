output "dc1_server_url" {
  value = module.dc1.consul_public_endpoint_url
}

output "dc2_server_url" {
  value = module.dc2.consul_public_endpoint_url
}

output "client_lb_address" {
  value = "http://${aws_lb.example_client_app.dns_name}:9090/ui"
}

//output "private_subnets" {
//  value = module.dc1_vpc.private_subnets
//}

output "dc1_server_bootstrap_token" {
  value     = module.dc1.bootstrap_token_id
  sensitive = true
}

output "dc2_server_bootstrap_token" {
  value     = module.dc2.bootstrap_token_id
  sensitive = true
}
