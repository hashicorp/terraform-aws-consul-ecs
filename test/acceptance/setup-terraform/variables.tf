# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  default     = "us-west-2"
  description = "AWS region"
}

variable "role_arn" {
  default     = ""
  description = "AWS role for the AWS provider to assume when running these templates."
}

variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}

variable "launch_type" {
  type        = string
  description = "The ECS launch type for the cluster. Either EC2 or FARGATE."
}

variable "enable_hcp" {
  description = "Whether to spin up an HCP Consul cluster."
  type        = bool
}

variable "instance_count" {
  description = "Number of EC2 instances to create for the EC2 launch type (if enabled)."
  type        = number
  default     = 4
}

variable "instance_type" {
  description = "The instance type for EC2 instances if launch type is EC2."
  type        = string
  default     = "t3a.micro"
}

variable "consul_version" {
  description = "The default Consul version for both CE and Enterprise. Must be a valid MAJOR.MINOR.PATCH version string. This is used when edition-specific versions are not provided."
  type        = string
  default     = ""

  validation {
    condition     = var.consul_version == "" || can(regex("^\\d+[.]\\d+[.]\\d+$", var.consul_version))
    error_message = "Must be a valid MAJOR.MINOR.PATCH version string or empty."
  }
}

variable "consul_ce_version" {
  description = "The Consul Community Edition version. Must be a valid MAJOR.MINOR.PATCH version string. If not set, consul_version will be used."
  type        = string
  default     = ""

  validation {
    condition     = var.consul_ce_version == "" || can(regex("^\\d+[.]\\d+[.]\\d+$", var.consul_ce_version))
    error_message = "Must be a valid MAJOR.MINOR.PATCH version string or empty."
  }
}

variable "consul_enterprise_version" {
  description = "The Consul Enterprise version. Must be a valid MAJOR.MINOR.PATCH version string. If not set, consul_version will be used."
  type        = string
  default     = ""

  validation {
    condition     = var.consul_enterprise_version == "" || can(regex("^\\d+[.]\\d+[.]\\d+$", var.consul_enterprise_version))
    error_message = "Must be a valid MAJOR.MINOR.PATCH version string or empty."
  }
}

variable "hcp_project_id" {
  description = "ID of the HCP project where the Consul specific resources will be created."
  type        = string
}
