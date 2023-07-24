# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "envoy_public_listener_port" {
  type = number
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_address      = "consul.dc1"
  outbound_only              = true
  envoy_public_listener_port = var.envoy_public_listener_port
}
