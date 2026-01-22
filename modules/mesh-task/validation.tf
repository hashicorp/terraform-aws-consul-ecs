# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  require_port_unless_no_port_true = !var.outbound_only && var.port == 0 ? tobool("ERROR: port must be set if outbound_only is false") : null
  require_listener_and_readiness_ports_to_be_different = (var.envoy_public_listener_port == var.envoy_readiness_port) ? tobool("ERROR: envoy_public_listener_port should not conflict with envoy_readiness_port") : null
  require_namespace_if_partition_is_set = (var.consul_partition != "" && var.consul_namespace == "") ? tobool("ERROR: consul_namespace must be set if consul_partition is set") : null
  require_partition_if_namespace_is_set = (var.consul_namespace != "" && var.consul_partition == "") ? tobool("ERROR: consul_partition must be set if consul_namespace is set") : null
  require_no_additional_task_policies_with_passed_role = (!var.create_task_role && length(var.additional_task_role_policies) > 0) ? tobool("ERROR: cannot set additional_task_role_policies when create_task_role=false") : null
  require_no_additional_execution_policies_with_passed_role = (!var.create_execution_role && length(var.additional_execution_role_policies) > 0) ? tobool("ERROR: cannot set additional_execution_role_policies when create_execution_role=false") : null
  require_ec2_compability_for_tproxy_support = var.enable_transparent_proxy && (length(var.requires_compatibilities) != 1 || var.requires_compatibilities[0] != "EC2") ? tobool("ERROR: transparent proxy is supported only in ECS EC2 mode.") : null
  require_tproxy_enabled_for_consul_dns = var.enable_consul_dns && !var.enable_transparent_proxy ? tobool("ERROR: var.enable_transparent_proxy must be set to true for Consul DNS to be enabled.") : null
}