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
  description = "The Consul version. Must a valid MAJOR.MINOR.PATCH version string."
  type        = string

  validation {
    condition     = can(regex("^\\d+[.]\\d+[.]\\d+$", var.consul_version))
    error_message = "Must a valid MAJOR.MINOR.PATCH version string."
  }
}
