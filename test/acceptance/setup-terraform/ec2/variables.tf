# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "ecs_cluster_name" {
  type = string
}

variable "instance_count" {
  type = number
}

variable "instance_type" {
  type = string
}

variable "name" {
  type = string
}

variable "tags" {
  type = any
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type        = any
}
