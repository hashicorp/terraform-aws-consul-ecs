# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0
provider "aws" {
  region = "us-west-2"
}

variable "envoy_readiness_port" {
  type = number
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_hosts  = "consul.dc1"
  outbound_only        = true
  envoy_readiness_port = var.envoy_readiness_port

  enable_transparent_proxy = false
}