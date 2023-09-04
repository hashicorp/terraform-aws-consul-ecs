# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "name" {
  description = "Name prefix that will be used for the client app."
  type        = string
}

variable "datacenter" {
  description = "Consul datacenter where the client app will be registered."
  type        = string
}

variable "consul_partition" {
  description = "Consul admin partition where the client app will be registered."
  type        = string
  default     = "default"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group where the client app task's logs will be pushed to."
  type        = string
}

variable "port" {
  description = "Port that the client application listens on."
  type        = number
}

variable "consul_server_address" {
  description = "Address of Consul servers."
  type        = string
}

variable "consul_server_ca_cert_arn" {
  description = "ARN of the secret that contains the Consul's CA cert for communication with the Consul servers."
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to be used in the client app's task."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the client app will be deployed to."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs into which the task should be deployed."
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet IDs into which the client's ALB will be deployed."
  type        = list(string)
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_default_security_group_id" {
  description = "ID of the VPC's default security group"
  type        = string
}

variable "consul_server_lb_security_group_id" {
  description = "ID of the Consul server LB's security group"
  type        = string
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
  type        = string
}

variable "additional_task_role_policies" {
  description = "List of additional policy ARNs to attach to the task role."
  type        = list(string)
  default     = []
}