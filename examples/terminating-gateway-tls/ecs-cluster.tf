# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

resource "aws_ecs_cluster" "cluster_one" {
  name               = "${var.name}-1"
  capacity_providers = ["FARGATE"]
}

resource "aws_ecs_cluster" "cluster_two" {
  name               = "${var.name}-2"
  capacity_providers = ["FARGATE"]
}
