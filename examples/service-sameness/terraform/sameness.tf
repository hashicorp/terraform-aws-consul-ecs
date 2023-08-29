# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "consul_config_entry" "sameness_group_dc1_default_partition" {
  depends_on = [consul_peering.dc1-default-partition-dc2, consul_peering.dc1-part1-partition-dc2]

  kind      = "sameness-group"
  name      = "${local.datacenter_1}-default-sameness-group"
  partition = "default"
  provider  = consul.dc1-cluster

  config_json = jsonencode({
    DefaultForFailover = true
    IncludeLocal       = true
    Members = [
      { Partition = var.dc1_consul_admin_partition },
      { Peer = "${local.datacenter_2}-cluster" }
    ]
  })
}

resource "consul_config_entry" "sameness_group_dc1_part1_partition" {
  depends_on = [consul_peering.dc1-default-partition-dc2, consul_peering.dc1-part1-partition-dc2]

  kind      = "sameness-group"
  name      = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-sameness-group"
  partition = var.dc1_consul_admin_partition
  provider  = consul.dc1-cluster

  config_json = jsonencode({
    DefaultForFailover = true
    IncludeLocal       = true
    Members = [
      { Partition = "default" },
      { Peer = "${local.datacenter_2}-cluster" }
    ]
  })
}

resource "consul_config_entry" "sameness_group_dc2_default_partition" {
  depends_on = [consul_peering.dc1-default-partition-dc2, consul_peering.dc1-part1-partition-dc2]

  kind      = "sameness-group"
  name      = "${local.datacenter_2}-default-sameness-group"
  partition = "default"
  provider  = consul.dc2-cluster

  config_json = jsonencode({
    DefaultForFailover = true
    IncludeLocal       = true
    Members = [
      { Peer = "${local.datacenter_1}-default-cluster" },
      { Peer = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-cluster" }
    ]
  })
}

resource "consul_config_entry" "export_dc2_server_app" {
  depends_on = [consul_config_entry.sameness_group_dc2_default_partition]

  kind     = "exported-services"
  name     = "default"
  provider = consul.dc2-cluster

  config_json = jsonencode({
    Name = "default"
    Services = [
      {
        Name = module.server_app_dc2.consul_service_name
        Consumers = [
          {
            SamenessGroup = "${local.datacenter_2}-default-sameness-group"
          }
        ]
      }
    ]
  })
}

resource "consul_config_entry" "export_dc1_default_server_app" {
  depends_on = [consul_config_entry.sameness_group_dc1_default_partition]

  kind     = "exported-services"
  name     = "default"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Name = "default"
    Services = [
      {
        Name = module.server_app_dc1.consul_service_name
        Consumers = [
          {
            SamenessGroup = "${local.datacenter_1}-default-sameness-group"
          }
        ]
      }
      # {
      #   Name = module.dc1_gateway_default_partition.name
      #   Consumers = [
      #     {
      #       SamenessGroup = "${local.datacenter_1}-default-sameness-group"
      #     }
      #   ]
      # }
    ]
  })
}

resource "consul_config_entry" "export_dc1_part1_server_app" {
  depends_on = [consul_config_entry.sameness_group_dc1_part1_partition]

  kind      = "exported-services"
  name      = var.dc1_consul_admin_partition
  partition = var.dc1_consul_admin_partition

  provider = consul.dc1-cluster

  config_json = jsonencode({
    Name = var.dc1_consul_admin_partition
    Services = [
      {
        Name = module.server_app_dc1_part1.consul_service_name
        Consumers = [
          {
            SamenessGroup = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-sameness-group"
          }
        ]
      }
      # {
      #   Name = module.dc1_gateway_part1_partition.name
      #   Consumers = [
      #     {
      #       SamenessGroup = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-sameness-group"
      #     }
      #   ]
      # }
    ]
  })
}

resource "consul_config_entry" "dc1_server_app_intentions" {
  depends_on = [consul_config_entry.sameness_group_dc1_default_partition]
  kind       = "service-intentions"
  name       = module.server_app_dc1.consul_service_name
  provider   = consul.dc1-cluster
  partition  = "default"

  config_json = jsonencode({
    Sources = [
      {
        Name          = module.client_app_dc1.consul_service_name
        Action        = "allow"
        Namespace     = "default"
        SamenessGroup = "${local.datacenter_1}-default-sameness-group"
      }
    ]
  })
}

resource "consul_config_entry" "dc1_part1_server_app_intentions" {
  depends_on = [consul_config_entry.sameness_group_dc1_part1_partition]
  kind       = "service-intentions"
  name       = module.server_app_dc1_part1.consul_service_name
  provider   = consul.dc1-cluster
  partition  = var.dc1_consul_admin_partition

  config_json = jsonencode({
    Sources = [
      {
        Name          = module.client_app_dc1_part1.consul_service_name
        Action        = "allow"
        Namespace     = "default"
        SamenessGroup = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-sameness-group"
      }
    ]
  })
}

resource "consul_config_entry" "dc2_server_app_intentions" {
  depends_on = [consul_config_entry.sameness_group_dc2_default_partition]
  kind       = "service-intentions"
  name       = module.server_app_dc2.consul_service_name
  provider   = consul.dc2-cluster
  partition  = "default"

  config_json = jsonencode({
    Sources = [
      {
        Name          = module.client_app_dc2.consul_service_name
        Action        = "allow"
        Namespace     = "default"
        SamenessGroup = "${local.datacenter_2}-default-sameness-group"
      }
    ]
  })
}

resource "consul_config_entry" "dc2_proxy_defaults" {
  depends_on = [module.dc2_gateway]
  kind       = "proxy-defaults"
  name       = "global"
  provider   = consul.dc2-cluster
  partition  = "default"

  config_json = jsonencode({
    MeshGateway = {
      Mode = "local"
    }
  })
}

resource "consul_config_entry" "dc1_proxy_defaults" {
  depends_on = [module.dc1_gateway_default_partition]
  kind       = "proxy-defaults"
  name       = "global"
  provider   = consul.dc1-cluster
  partition  = "default"

  config_json = jsonencode({
    MeshGateway = {
      Mode = "local"
    }
  })
}

resource "consul_config_entry" "dc1_part1_proxy_defaults" {
  depends_on = [module.dc1_gateway_part1_partition]
  kind       = "proxy-defaults"
  name       = "global"
  provider   = consul.dc1-cluster
  partition  = var.dc1_consul_admin_partition

  config_json = jsonencode({
    MeshGateway = {
      Mode = "local"
    }
  })
}