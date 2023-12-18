# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter" {
  description = "Name of the consul datacenter."
  type        = string
  default     = "dc1"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
  type        = string
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type = object({
    vpc_id                    = string
    default_security_group_id = string
  })
}

variable "private_subnets" {
  description = "List of private subnet ids."
  type        = list(string)
}

variable "public_subnets" {
  description = "List of public subnet ids."
  type        = list(string)
}

variable "consul_server_startup_timeout" {
  description = "The number of seconds to wait for the Consul server to become available via its ALB before continuing. The default is 300s (5m), which should be enough in most cases."
  type        = number
  default     = 300
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "hashicorp/consul-enterprise:1.17.1-ent"
}

variable "consul_license" {
  description = "A Consul Enterprise license key. Requires consul_image to be set to a Consul Enterprise image."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the Consul server will be deployed to."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group where the server task's logs will be pushed to."
  type        = string
}