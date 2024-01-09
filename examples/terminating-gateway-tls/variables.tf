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
  description = "hashicorp alpine image"
  default     = "hashicorp/consul:1.17.0"
}

variable "tgw_certs_enabled" {
  description = "Whether to enable the TGW certs or not."
  type        = bool
  default     = false
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
  default = [
    #    {
    #      name =      "certs-efs"
    #      host_path =  "/efs/certs"
    #      efs_volume_configuration = {
    #          file_system_id = "fs-0dc6a2495461a06f7"
    #          root_directory = "/"
    #        }
    #    }
  ]
}