# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
}

variable "suffix" {
  description = "Suffix to append to resource names."
  type        = string
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type        = any
}

variable "consul_version" {
  description = "The Consul server version."
  type        = string
}
