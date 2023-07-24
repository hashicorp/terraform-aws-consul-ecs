# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "consul_ecs_config_file" {
  type = string
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_address = "consul.dc1.host"
  outbound_only         = true
  consul_ecs_config     = jsondecode(file("${path.module}/${var.consul_ecs_config_file}"))
}
