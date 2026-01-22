# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  require_port_unless_no_port_true                          = var.outbound_only || var.port != 0 ? null : assert(false, "port must be set if outbound_only is false")
  require_listener_and_readiness_ports_to_be_different      = var.envoy_public_listener_port != var.envoy_readiness_port ? null : assert(false, "envoy_public_listener_port should not conflict with envoy_readiness_port")
  require_namespace_if_partition_is_set                     = !(var.consul_partition != "" && var.consul_namespace == "") ? null : assert(false, "consul_namespace must be set if consul_partition is set")
  require_partition_if_namespace_is_set                     = !(var.consul_namespace != "" && var.consul_partition == "") ? null : assert(false, "consul_partition must be set if consul_namespace is set")
  require_no_additional_task_policies_with_passed_role      = var.create_task_role || length(var.additional_task_role_policies) == 0 ? null : assert(false, "cannot set additional_task_role_policies when create_task_role=false")
  require_no_additional_execution_policies_with_passed_role = var.create_execution_role || length(var.additional_execution_role_policies) == 0 ? null : assert(false, "cannot set additional_execution_role_policies when create_execution_role=false")
  require_ec2_compability_for_tproxy_support                = !(var.enable_transparent_proxy && (length(var.requires_compatibilities) != 1 || var.requires_compatibilities[0] != "EC2")) ? null : assert(false, "transparent proxy is supported only in ECS EC2 mode.")
  require_tproxy_enabled_for_consul_dns                     = !(var.enable_consul_dns && !var.enable_transparent_proxy) ? null : assert(false, "var.enable_transparent_proxy must be set to true for Consul DNS to be enabled.")
}