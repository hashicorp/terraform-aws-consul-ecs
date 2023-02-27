# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

// We test this with a Terraform plan only.

provider "aws" {
  region = "us-west-2"
}

variable "application_shutdown_delay_seconds" {
  type    = number
  default = null
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  retry_join    = ["test"]
  outbound_only = true

  application_shutdown_delay_seconds = var.application_shutdown_delay_seconds
}
