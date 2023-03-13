# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter" {
  description = "Name of the consul datacenter."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type = object({
    vpc_id                    = string
    default_security_group_id = string
  })
}

variable "private_subnets" {
  description = "List of private subnet ids."
  type        = list(string)
}

variable "public_subnets" {
  description = "List of public subnet ids."
  type        = list(string)
}

variable "primary_datacenter" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = string
  default     = ""
}

variable "cluster" {
  description = "The ARN of the ECS cluster to deploy the mesh gateway into."
  type        = string
}

variable "retry_join" {
  description = "List of addresses for the gateway to join."
  type        = list(string)
}

variable "log_group_name" {
  description = "Name of the AWS Cloud Watch log group."
  type        = string
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "consul_http_addr" {
  description = "Consul server HTTP address."
  type        = string
}

variable "ca_cert_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate. A CA certificate will automatically be created and stored in Secrets Manager if TLS is enabled and this variable is not provided."
  type        = string
  default     = ""
}

variable "ca_key_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate key. A CA certificate key will automatically be created and stored in Secrets Manager if TLS is enabled and this variable is not provided."
  type        = string
  default     = ""
}

variable "gossip_encryption_enabled" {
  description = "Whether or not to enable gossip encryption."
  type        = bool
  default     = false
}

variable "gossip_key_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul gossip encryption key. A gossip encryption key will be generated if gossip encryption is enabled and this is not provided."
  type        = string
  default     = ""
}

variable "wan_address" {
  description = "The WAN address of the mesh gateway."
  type        = string
  default     = ""
}

variable "wan_port" {
  description = "The WAN port of the mesh gateway. Default is 8443"
  type        = number
  default     = 8443
}

variable "additional_task_role_policies" {
  description = "List of additional policy ARNs to attach to the task role."
  type        = list(string)
  default     = []
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use in all tasks."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.5.0"
}
