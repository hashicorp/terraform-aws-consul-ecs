# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "consul_server_hosts" {
  description = "Address of Consul servers."
  type        = string
}

variable "consul_ca_cert_arn" {
  description = "ARN of the secret that contains the Consul's CA cert for communication with the Consul servers."
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet ids."
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the Consul server will be deployed to."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group where the server task's logs will be pushed to."
  type        = string
}