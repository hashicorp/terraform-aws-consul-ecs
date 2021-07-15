locals {
  require_retry_join               = (var.consul_server_service_name == "" && var.retry_join == "") ? file("ERROR: either consul_server_service_name or retry_join must be set so that Consul clients can join the cluster") : null
  require_port_unless_no_port_true = !var.outbound_only && var.port == 0 ? file("ERROR: port must be set if outbound_only is false") : null
  require_ca_cert_if_tls_enabled   = (var.tls && var.consul_server_ca_cert_arn == "") ? file("ERROR: Consul CA certificate is required when TLS is enabled") : null
}
