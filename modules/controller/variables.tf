# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "ganeshrockz/ecs"
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the controller will be running."
  type        = string
}

variable "region" {
  description = "AWS region of the ECS cluster."
  type        = string
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task."
  type        = list(string)
  default     = ["EC2", "FARGATE"]
}

variable "launch_type" {
  description = "Launch type on which to run service. Valid values are EC2 and FARGATE."
  type        = string
  default     = "FARGATE"
}

variable "consul_bootstrap_token_secret_arn" {
  description = "The ARN of the AWS SecretsManager secret containing the token to be used by this controller. The token needs to have at least `acl:write` and `node:write` privileges in Consul."
  type        = string
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "iam_role_path" {
  description = "IAM roles at this path will be permitted to login to the Consul AWS IAM auth method configured by this controller."
  type        = string
  default     = "/consul-ecs/"
}

variable "subnets" {
  description = "Subnets where the controller task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
  type        = list(string)
}

variable "consul_server_address" {
  description = "Address of the consul server host"
  type        = string
}

variable "skip_server_watch" {
  description = "If true, setting this prevents the consul-dataplane and consul-ecs-control-plane from watching the Consul servers for changes. This is useful for situations where Consul servers are behind a load balancer."
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "The prefix that will be used for all resources created by this module. Must be non-empty."
  type        = string
}

variable "consul_server_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal RPC and HTTP interfaces."
  type        = string
  default     = ""
}

variable "consul_grpc_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal RPC. Overrides var.consul_server_ca_cert_arn"
  type        = string
  default     = ""
}

variable "consul_https_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides var.consul_server_ca_cert_arn"
  type        = string
  default     = ""
}

variable "assign_public_ip" {
  description = "Configure the ECS Service to assign a public IP to the task. This is required if running tasks on a public subnet."
  type        = bool
  default     = false
}

variable "consul_partitions_enabled" {
  description = "Enable admin partitions [Consul Enterprise]."
  type        = bool
  default     = false
}

variable "tls" {
  description = "Whether to enable TLS for the controller to control plane traffic."
  type        = bool
  default     = false
}

variable "tls_server_name" {
  description = "The server name to use as the SNI host when connecting via TLS for Consul's HTTP and gRPC interfaces."
  type        = string
  default     = ""
}

variable "ca_cert_file" {
  description = <<-EOT
  The CA certificate file for Consul's internal HTTP and gRPC interfaces. `CONSUL_HTTPS_CACERT_PEM` and 
  `CONSUL_GRPC_CACERT_PEM` takes a higher precedence when configuring TLS settings in the controller."
  EOT
  type        = string
  default     = ""
}

variable "consul_partition" {
  description = "Admin partition the controller will manage [Consul Enterprise]."
  type        = string
  default     = "default"
}

variable "security_groups" {
  description = "Configure the ECS service with security groups. If not specified, the default security group for the VPC is used."
  type        = list(string)
  default     = []
}

variable "additional_execution_role_policies" {
  description = "List of additional policy ARNs to attach to the execution role."
  type        = list(string)
  default     = []
}

variable "http_tls_config" {
  type        = any
  default     = {}
  description = <<-EOT
  This accepts HTTP specific TLS configuration based on the `consulServers.http` schema present in https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json.
  If empty, values of `var.tls`, `var.tls_server_name` and `var.ca_cert_file` will be used to configure TLS settings for HTTP. 
  EOT

  validation {
    error_message = "Only the 'port', 'https', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in http_tls_config."
    condition = alltrue([
      for key in keys(var.http_tls_config) :
      contains(["port", "https", "tls", "tlsServerName", "caCertFile"], key)
    ])
  }
}

variable "grpc_tls_config" {
  type        = any
  default     = {}
  description = <<-EOT
  This accepts gRPC specific TLS configuration based on the `consulServers.grpc` schema present in https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json.
  If empty, values of `var.tls`, `var.tls_server_name` and `var.ca_cert_file` will be used to configure TLS settings for gRPC. 
  EOT

  validation {
    error_message = "Only the 'port', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in grpc_tls_config."
    condition = alltrue([
      for key in keys(var.grpc_tls_config) :
      contains(["port", "tls", "tlsServerName", "caCertFile"], key)
    ])
  }
}