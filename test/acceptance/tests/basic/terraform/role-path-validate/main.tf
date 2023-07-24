# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "iam_role_path" {
  type = string
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  outbound_only = true
  consul_server_address = "consul.dc1.host"

  iam_role_path = var.iam_role_path
}
