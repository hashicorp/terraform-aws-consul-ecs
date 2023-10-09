# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  // parse the consul version from the provided image: ["1", "12", "2"]
  # consul_image_version_parts = regex(":.*(\\d+)[.](\\d+)[.](\\d+)", var.consul_image)
  is_consul_1_14_plus        = true//tonumber(local.consul_image_version_parts[1]) >= 14
}
