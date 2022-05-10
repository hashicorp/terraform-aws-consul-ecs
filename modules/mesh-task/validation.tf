locals {
  require_port_unless_no_port_true      = !var.outbound_only && var.port == 0 ? file("ERROR: port must be set if outbound_only is false") : null
  require_ca_cert_if_tls_enabled        = (var.tls && var.consul_server_ca_cert_arn == "") ? file("ERROR: consul_server_ca_cert_arn must be set if tls is true") : null
  require_consul_http_addr_if_acls      = (var.acls && var.consul_http_addr == "") ? file("ERROR: consul_http_addr must be set if acls is true") : null
  require_namespace_if_partition_is_set = (var.consul_partition != "" && var.consul_namespace == "") ? file("ERROR: consul_namespace must be set if consul_partition is set") : null
  require_partition_if_namespace_is_set = (var.consul_namespace != "" && var.consul_partition == "") ? file("ERROR: consul_partition must be set if consul_namespace is set") : null
}
