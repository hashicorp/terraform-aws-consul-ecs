# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "ecs-perf"
}

variable "datacenter" {
  type    = string
  default = "dc1"
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
  default     = "hashicorpdev/consul-ecs:latest"
}

variable "desired_service_groups" {
  type    = number
  default = 1
}

variable "server_instances_per_group" {
  type    = number
  default = 1
}

variable "client_instances_per_group" {
  type    = number
  default = 1
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "consul_license" {
  type = string
}