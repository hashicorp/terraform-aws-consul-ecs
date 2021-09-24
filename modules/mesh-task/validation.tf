locals {
  require_port_unless_no_port_true           = !var.outbound_only && var.port == 0 ? file("ERROR: port must be set if outbound_only is false") : null
  require_ca_cert_if_tls_enabled             = (var.tls && var.consul_server_ca_cert_arn == "") ? file("ERROR: consul_server_ca_cert_arn must be set if tls is true") : null
  require_client_token_if_acls_enabled       = (var.acls && var.consul_client_token_secret_arn == "") ? file("ERROR: consul_client_token_secret_arn must be set if acls is true") : null
  require_secret_name_prefix_if_acls_enabled = (var.acls && var.acl_secret_name_prefix == "") ? file("ERROR: acl_secret_name_prefix must be set if acls is true") : null
}
