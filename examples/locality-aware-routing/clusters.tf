# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "cluster" {
  source = "./cluster"
  name   = var.name
}