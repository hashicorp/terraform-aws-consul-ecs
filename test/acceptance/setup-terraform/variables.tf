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
  description = "The Consul version. Supported versions: 1.12, 1.13, or 1.14. Must be a full MAJOR.MINOR.PATCH version string"
  type        = string

  validation {
    # Sanity check that we are using a supported version.
    condition = anytrue([
      can(regex("1.12.\\d+", var.consul_version)),
      can(regex("1.13.\\d+", var.consul_version)),
      can(regex("1.14.\\d+", var.consul_version)),
    ])
    error_message = "Only Consul versions 1.12, 1.13, and 1.14 are supported. Must a valid MAJOR.MINOR.PATCH version string."
  }
}
