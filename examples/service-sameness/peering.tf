# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "consul_config_entry" "mesh_dc1" {
  depends_on = [module.dc1]

  kind     = "mesh"
  name     = "mesh"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Peering = {
      PeerThroughMeshGateways = true
    }
  })
}

resource "consul_config_entry" "mesh_dc2" {
  depends_on = [module.dc2]

  kind     = "mesh"
  name     = "mesh"
  provider = consul.dc2-cluster

  config_json = jsonencode({
    Peering = {
      PeerThroughMeshGateways = true
    }
  })
}

resource "consul_peering_token" "token1" {
  depends_on = [module.dc1_gateway_default_partition, module.dc2_gateway]
  provider   = consul.dc2-cluster
  peer_name  = "${local.datacenter_1}-default-cluster"
}

resource "consul_peering" "dc1-default-partition-dc2" {
  provider = consul.dc1-cluster

  peer_name     = "${local.datacenter_2}-cluster"
  peering_token = consul_peering_token.token1.peering_token
  partition     = "default"
}

resource "consul_peering_token" "token2" {
  depends_on = [module.dc1_gateway_default_partition, module.dc2_gateway]
  provider   = consul.dc2-cluster
  peer_name  = "${local.datacenter_1}-${var.dc1_consul_admin_partition}-cluster"
}

resource "consul_peering" "dc1-part1-partition-dc2" {
  provider = consul.dc1-cluster

  peer_name     = "${local.datacenter_2}-cluster"
  peering_token = consul_peering_token.token2.peering_token
  partition     = var.dc1_consul_admin_partition
}