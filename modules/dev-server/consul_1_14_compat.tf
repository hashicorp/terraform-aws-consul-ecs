# Copyright IBM Corp. 2021, 2026
# SPDX-License-Identifier: MPL-2.0

locals {
  // parse the consul version from the provided image: ["1", "12", "2"]
  consul_image_version_parts = regex(":.*(\\d+)[.](\\d+)[.](\\d+)", var.consul_image)
  // Compare major and minor. Checking the minor alone misreads Consul 2.x as
  // pre-1.14 (2.1.0 -> minor 1), which selects the legacy `ports.grpc` TLS
  // config that Consul 2.x rejects at startup.
  is_consul_1_14_plus = (
    tonumber(local.consul_image_version_parts[0]) > 1 ||
    (tonumber(local.consul_image_version_parts[0]) == 1 && tonumber(local.consul_image_version_parts[1]) >= 14)
  )
}
