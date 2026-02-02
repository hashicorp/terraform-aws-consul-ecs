# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "consul_license" {
  description = "A Consul Enterprise license key."
  type        = string
  sensitive   = true
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
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.9.3"
}

variable "consul_server_startup_timeout" {
  description = "The number of seconds to wait for the Consul server to become available via its ALB before continuing. The default is 300s (5m), which should be enough in most cases."
  type        = number
  default     = 300
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "hashicorp/consul-enterprise:1.21.5-ent"
}
