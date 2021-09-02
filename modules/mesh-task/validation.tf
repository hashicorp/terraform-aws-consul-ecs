locals {
  require_port_unless_no_port_true = ! var.outbound_only && var.port == 0 ? file("ERROR: port must be set if outbound_only is false") : null
  require_ca_cert_if_tls_enabled   = (var.tls && var.consul_server_ca_cert_arn == "") ? file("ERROR: consul_server_ca_cert_arn must be set if tls is true") : null
}
