# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "volumes" {
  type = any
}

module "test_client" {
  source  = "../../../../../../modules/mesh-task"
  family  = "family"
  volumes = var.volumes
  container_definitions = [{
    name = "basic"
  }]
  consul_server_address = "consul.dc1"
  outbound_only         = true
}
