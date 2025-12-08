# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "grpc_config_file" {
  type = string
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_hosts = "consul.dc1.host"
  outbound_only       = true
  grpc_config         = jsondecode(file("${path.module}/${var.grpc_config_file}"))

  enable_transparent_proxy = false
}