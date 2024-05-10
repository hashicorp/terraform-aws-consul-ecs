# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter_names" {
  description = "Names of Consul datacenters to use."
  type        = list(string)
  default     = ["dc1", "dc2"]

  validation {
    error_message = "Exactly two datacenter names are required."
    condition     = length(var.datacenter_names) == 2
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-west-2"
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use in all tasks."
  type        = string
  default     = "hashicorppreview/consul-ecs:0.8.1"
}

variable "consul_server_startup_timeout" {
  description = "The number of seconds to wait for the Consul server to become available via its ALB before continuing. The default is 300s (5m), which should be enough in most cases."
  type        = number
  default     = 300
}

variable "mesh_gateway_readiness_timeout" {
  description = "The number of seconds to wait for the Mesh gateway's service instance to become healthy in Consul, so that peering via the gateway can happen successfully. The default is 300s (5m), which should be enough in most cases."
  type        = number
  default     = 300
}
