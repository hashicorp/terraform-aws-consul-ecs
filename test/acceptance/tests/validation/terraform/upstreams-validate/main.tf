# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "upstreams_file" {
  type = string
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_hosts = "consul.dc1"
  outbound_only       = true
  upstreams           = jsondecode(file("${path.module}/${var.upstreams_file}"))

  enable_transparent_proxy = false
}
