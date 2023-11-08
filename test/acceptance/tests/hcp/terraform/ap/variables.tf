# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "Region."
  type        = string
}

variable "suffix_1" {
  description = "Suffix to add to all resource names in cluster 1."
  type        = string
}

variable "suffix_2" {
  description = "Suffix to add to all resource names in cluster 2."
  type        = string
}

variable "ecs_cluster_arns" {
  type        = list(string)
  description = "ECS cluster ARNs. Two are required, and only the first two are used."

  validation {
    error_message = "Two ECS clusters are required."
    condition     = length(var.ecs_cluster_arns) >= 2
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

variable "subnets" {
  description = "Subnets to deploy into."
  type        = list(string)
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "log_group_name" {
  description = "Name for cloudwatch log group."
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "hashicorp/consul-ecs:0.7.0"
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

variable "client_partition" {
  description = "The Consul partition that the client belongs to."
  type        = string
  default     = "part1"
}

variable "client_namespace" {
  description = "The Consul namespace that the client belongs to."
  type        = string
  default     = "ns1"
}

variable "server_partition" {
  description = "The Consul partition that the server belongs to."
  type        = string
  default     = "part2"
}

variable "server_namespace" {
  description = "The Consul namespace that the server belongs to."
  type        = string
  default     = "ns2"
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
