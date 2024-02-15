# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  default     = "us-west-2"
  description = "AWS region"
}

variable "hcp_project_id" {
  description = "ID of the project in HCP where the Consul server will be created."
  type        = string
}

variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "hashicorppreview/consul-ecs:0.7.3-dev"
}

variable "consul_dataplane_image" {
  description = "consul-dataplane Docker image."
  type        = string
  default     = "hashicorp/consul-dataplane:1.3.3"
}

variable "client_partition" {
  description = "The Consul partition to deploy the example client into."
  type        = string
  default     = "part1"
}

variable "client_namespace" {
  description = "The Consul namespace to deploy the example client into."
  type        = string
  default     = "ns1"
}

variable "server_partition" {
  description = "The Consul partition to deploy the example server into."
  type        = string
  default     = "part2"
}

variable "server_namespace" {
  description = "The Consul namespace to deploy the example server into."
  type        = string
  default     = "ns2"
}
