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

variable "private_key" {
  type = string
  description = "Private key to be used to access the EC2 instances."
  default = "/Users/kumarkavish/Documents/AWS/kavishECS.pem"
}

variable "tgw_certs_enabled" {
  description = "Whether to enable the TGW certs or not."
  type        = bool
  default     = true
}

variable "certs_mount_path" {
  description = "Path to mount the EFS volume on the EC2 container."
  type        = string
  default     = "/mnt/efs"
}

variable "cert_paths" {
  description = "paths of the certs mounted"
    type        = object({
      cert_path = string
      key_path = string
    })
#  default = {
#    cert_path = ""
#    key_path = ""
#  }
    default     = {
      cert_path = "/mnt/efs/gateway.crt"
      key_path = "/mnt/efs/gateway.key"
    }
}

variable "volumes" {
  description = "List of volumes to include in the aws_ecs_task_definition resource."
  type        = any
  default     = [
    {
      name =      "certs-efs"
      host_path =  "/mnt/efs"
      efs_volume_configuration = {
          file_system_id = "fs-0f82df761214b502c"
          root_directory = "/"
        }
    }
  ]
}