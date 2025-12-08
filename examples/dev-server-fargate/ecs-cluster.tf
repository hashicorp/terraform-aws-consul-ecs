# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

resource "aws_ecs_cluster" "this" {
  name               = var.name
  capacity_providers = ["FARGATE"]
}
