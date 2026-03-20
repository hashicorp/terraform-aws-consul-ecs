# Copyright (c) HashiCorp, Inc.
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
  description = "The Consul server version. HCP Consul is Enterprise only."
  type        = string
}

variable "consul_ce_version" {
  description = "The Consul Community Edition version (not used for HCP)."
  type        = string
  default     = ""
}

variable "consul_enterprise_version" {
  description = "The Consul Enterprise version. If set, this will be used instead of consul_version for HCP."
  type        = string
  default     = ""
}
