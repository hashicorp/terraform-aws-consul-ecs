# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name prefix that will be used for the server app."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group where the server app task's logs will be pushed to."
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

variable "consul_ecs_image" {
  description = "Consul ECS image to be used in the server app's task."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the server app will be deployed to."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs into which the task should be deployed."
  type        = list(string)
}

variable "server_instances_per_group" {
  type    = number
  default = 1
}

variable "client_instances_per_group" {
  type    = number
  default = 1
}

variable "additional_task_role_policies" {
  description = "List of additional policy ARNs to attach to the task role."
  type        = list(string)
  default     = []
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}