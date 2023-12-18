# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "ecs_cluster_arns" {
  type        = list(string)
  description = "ARNs of ECS clusters. One is required."

  validation {
    error_message = "At least one ECS cluster is required."
    condition     = length(var.ecs_cluster_arns) >= 1
  }
}

variable "vpc_id" {
  description = "The ID of the VPC for all resources."
  type        = string
}

variable "route_table_ids" {
  description = "IDs of the route tables for peering with HVN."
  type        = list(string)
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnets to deploy into."
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnets to deploy into."
}
variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "suffix" {
  type        = string
  default     = "nosuffix"
  description = "Suffix to add to all resource names."
}

variable "region" {
  type        = string
  description = "Region."
}

variable "log_group_name" {
  type        = string
  description = "Name for cloudwatch log group."
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "consul_image" {
  description = "Consul Docker image for Consul client agents in ECS."
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "hashicorp/consul-ecs:0.7.1"
}

variable "consul_server_address" {
  description = "Address of the consul server host"
  type        = string
}

variable "bootstrap_token_secret_arn" {
  description = "ARN of the secret holding the Consul bootstrap token."
  type        = string
}

variable "consul_ca_cert_secret_arn" {
  description = "ARN of the secret holding the Consul CA certificate."
  type        = string
  default     = ""
}

variable "http_port" {
  description = "Port where the server's HTTP interface is exposed"
  type        = number
  default     = 443
}

variable "grpc_port" {
  description = "Port where the server's gRPC interface is exposed"
  type        = number
  default     = 8502
}