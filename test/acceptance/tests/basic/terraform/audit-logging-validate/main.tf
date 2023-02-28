# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "audit_logging" {
  type    = bool
  default = false
}

variable "acls" {
  type    = bool
  default = false
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  outbound_only = true
  retry_join    = ["test"]

  audit_logging    = var.audit_logging
  consul_http_addr = "test"
  acls             = var.acls
}
