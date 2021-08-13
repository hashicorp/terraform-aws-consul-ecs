output "consul_elb_url" {
  value = module.consul-server.consul_elb
}

output "bootstrap_token" {
  value = random_uuid.bootstrap_token.result
}
