locals {
  require_port_unless_no_port_true                          = !var.outbound_only && var.port == 0 ? file("ERROR: port must be set if outbound_only is false") : null
  require_namespace_if_partition_is_set                     = (var.consul_partition != "" && var.consul_namespace == "") ? file("ERROR: consul_namespace must be set if consul_partition is set") : null
  require_partition_if_namespace_is_set                     = (var.consul_namespace != "" && var.consul_partition == "") ? file("ERROR: consul_partition must be set if consul_namespace is set") : null
  require_no_additional_task_policies_with_passed_role      = (!var.create_task_role && length(var.additional_task_role_policies) > 0) ? file("ERROR: cannot set additional_task_role_policies when create_task_role=false") : null
  require_no_additional_execution_policies_with_passed_role = (!var.create_execution_role && length(var.additional_execution_role_policies) > 0) ? file("ERROR: cannot set additional_execution_role_policies when create_execution_role=false") : null
  require_https_if_https_ca_cert_provided                   = var.consul_https_ca_cert_arn != "" && !var.consul_server_https ? file("ERROR: consul_https_ca_cert_arn cannot be provided when consul_server_https=false") : null
}
