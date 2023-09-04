# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name prefix that will be used for the controller."
  type        = string
}

variable "consul_partition" {
  description = "Consul admin partition where the controller will be registered."
  type        = string
  default     = "default"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group where the controller task's logs will be pushed to."
  type        = string
}

variable "consul_server_hosts" {
  description = "Address of Consul servers."
  type        = string
}

variable "consul_server_bootstrap_token_arn" {
  description = "ARN of the secret that contains the Consul server's bootstrap token."
  type        = string
}

variable "consul_ca_cert_arn" {
  description = "ARN of the secret that contains the Consul's CA cert for communication with the Consul servers."
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to used for the controller task."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the controller will be deployed to."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs into which the task should be deployed."
  type        = list(string)
}