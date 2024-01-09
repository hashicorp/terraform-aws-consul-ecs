# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "consul-ecs"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
  type        = string
}

variable "consul_image" {
  type        = string
  description = "hashicorp consul image"
  default     = "hashicorp/consul:latest"
}

variable "certs_mount_path" {
  description = "Path to mount the EFS volume on the EC2 container."
  type        = string
  default     = "/efs/certs"
}

variable "cert_paths" {
  description = "paths of the certs mounted"
  type = object({
    cert_path = string
    key_path  = string
    ca_path   = string
  })
  default = {
    cert_path = "/efs/gateway.cert"
    key_path  = "/efs/gateway.key"
    ca_path   = "/efs/ca.cert"
  }
}

variable "volumes" {
  description = "List of volumes to include in the aws_ecs_task_definition resource."
  type        = any
  default     = []
}