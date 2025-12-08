# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

module "cluster1" {
  source = "./cluster"
  name   = "${var.name}-${local.datacenter_1}-default"
}

module "cluster2" {
  source = "./cluster"
  name   = "${var.name}-${local.datacenter_1}-${var.dc1_consul_admin_partition}"
}

module "cluster3" {
  source = "./cluster"
  name   = "${var.name}-${local.datacenter_2}-default"
}