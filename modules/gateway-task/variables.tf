# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This is used by default as the Consul service name if `consul_service_name` is not provided."
  type        = string
}

variable "gateway_count" {
  description = "Number of gateways to deploy to ECS."
  type        = number
  default     = 1
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the gateway will be running."
  type        = string
}

variable "consul_service_name" {
  description = "The name the gateway service will be registered as in Consul. Defaults to the Task family name. Always suffixed with the gateway kind."
  type        = string
  default     = ""
}

variable "consul_service_tags" {
  description = "A list of tags included in the Consul gateway registration."
  type        = list(string)
  default     = []
}

variable "consul_service_meta" {
  description = "A map of metadata that will be used for the Consul gateway registration"
  type        = map(string)
  default     = {}
}

variable "consul_partition" {
  description = "The Consul admin partition to use to register this gateway [Consul Enterprise]."
  type        = string
  default     = ""
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

variable "cpu" {
  description = "Number of cpu units used by the task."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Amount (in MiB) of memory used by the task."
  type        = number
  default     = 512
}

variable "iam_role_path" {
  description = "The path where IAM roles will be created."
  type        = string
  default     = "/consul-ecs/"

  validation {
    error_message = "The iam_role_path must begin with '/'."
    condition     = var.iam_role_path != "" && substr(var.iam_role_path, 0, 1) == "/"
  }
}

variable "additional_task_role_policies" {
  description = "List of additional policy ARNs to attach to the task role."
  type        = list(string)
  default     = []
}

variable "additional_execution_role_policies" {
  description = "List of additional policy ARNs to attach to the execution role."
  type        = list(string)
  default     = []
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "hashicorp/consul:1.17.0"
}

variable "consul_server_hosts" {
  description = "Address of the Consul servers. This can be an IP address, a DNS name, or an `exec=` string specifying a script that outputs IP addresses. Refer to https://github.com/hashicorp/go-netaddrs#summary for details. This variable should not specify the port. Instead, use var.http_config.port and var.grpc_config.port to change the server HTTP and gRPC ports."
  type        = string
}

variable "skip_server_watch" {
  description = "Set this to true to prevent the consul-dataplane and consul-ecs-health-sync containers from watching the Consul servers for changes. This is useful for situations where Consul servers are behind a load balancer."
  type        = bool
  default     = false
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "hashicorppreview/consul-ecs:0.8.0-dev"
}

variable "consul_dataplane_image" {
  description = "consul-dataplane Docker image."
  type        = string
  default     = "hashicorppreview/consul-dataplane:1.4.0-dev"
}

variable "envoy_readiness_port" {
  description = "The port that is exposed by Envoy to indicate it's readiness. ECS uses this port to detect envoy's readiness and start the app containers depending on this."
  type        = number
  default     = 22000

  validation {
    error_message = "The envoy_readiness_port must be greater than 0 and less than or equal to 65535."
    condition     = var.envoy_readiness_port > 0 && var.envoy_readiness_port <= 65535
  }

  validation {
    error_message = "The envoy_readiness_port must not conflict with the following ports that are reserved for Consul and Envoy: 8300, 8301, 8302, 8500, 8501, 8502, 8600, 10000, 19000."
    condition = !contains([
      8600,  // consul dns
      19000, // envoy admin port
    ], var.envoy_readiness_port)
  }
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "consul_https_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the CA certificate for Consul's HTTPS interface. Overrides var.consul_ca_cert_arn"
  type        = string
  default     = ""
}

variable "consul_grpc_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC interface. Overrides var.consul_ca_cert_arn"
  type        = string
  default     = ""
}

variable "service_token_auth_method_name" {
  description = "The name of the Consul Auth Method to login to for service tokens."
  type        = string
  default     = "iam-ecs-service-token"
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "tls" {
  description = "Whether to enable TLS for the communication between gateway-task and Consul's HTTP and gRPC interfaces."
  type        = bool
  default     = false
}

variable "tls_server_name" {
  description = "The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces. This is the default value used when grpc_config.tlsServerName or http_config.tlsServerName is unset."
  type        = string
  default     = ""
}

variable "consul_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces. This is the default CA certificate used if consul_grpc_ca_cert_arn or consul_https_ca_cert_arn is not set."
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs for the gateway task."
  type        = bool
  default     = false
}

variable "kind" {
  description = "Gateway kind."
  type        = string

  validation {
    error_message = "Gateway kind must be one of 'mesh-gateway', 'terminating-gateway' or 'api-gateway'."
    condition     = contains(["mesh-gateway", "terminating-gateway", "api-gateway"], var.kind)
  }
}

variable "lan_address" {
  description = "LAN address for the gateway. Defaults to the task address."
  type        = string
  default     = ""
}

variable "lan_port" {
  description = "LAN port for the gateway. Defaults to 8443 if not specified."
  type        = number
  default     = 0
}

variable "wan_address" {
  description = "WAN address for the gateway. Defaults to the task address."
  type        = string
  default     = ""
}

variable "wan_port" {
  description = "WAN port for the gateway. Defaults to the lan_port if not specified."
  type        = number
  default     = 0
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "security_groups" {
  description = "Security group IDs that will be attached to the gateway. The default security group will be used if this is not specified. Required when lb_enabled is true so ingress rules can be added for the security groups."
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = "Subnet IDs where the gateway task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Configure the ECS Service to assign a public IP to the task. This is required if running tasks on a public subnet."
  type        = bool
  default     = false
}

variable "lb_enabled" {
  description = "Whether to create an Elastic Load Balancer for the task to allow public ingress to the gateway."
  type        = bool
  default     = false
}

variable "lb_vpc_id" {
  description = "The VPC identifier for the load balancer. Required when lb_enabled is true."
  type        = string
  default     = ""
}

variable "lb_subnets" {
  description = "Subnet IDs to attach to the load balancer. These must be public subnets if you wish to access the load balancer externally. Required when lb_enabled is true."
  type        = list(string)
  default     = []
}

variable "lb_ingress_rule_cidr_blocks" {
  description = "CIDR blocks that are allowed access to the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "lb_create_security_group" {
  description = "Whether to create a security group and ingress rule for the gateway task."
  type        = bool
  default     = true
}

variable "lb_modify_security_group" {
  description = "Whether to modify an existing security group with an ingress rule for the gateway task. The lb_create_security_group variable must be set to false when using this option."
  type        = bool
  default     = false
}

variable "lb_modify_security_group_id" {
  description = "The ID of the security group to modify with an ingress rule for the gateway task. Required when lb_modify_security_group is true."
  type        = string
  default     = ""
}

variable "custom_load_balancer_config" {
  description = <<-EOT
  Load balancer config that will applied to the ECS service backing the gateway task.
  The gateway submodule by default creates an NLB with backing listeners that attach the LB
  to the gateway ECS task. When configuring API gateways, users might need to deploy an ALB
  and add listeners that target the API gateway's ECS task. This field can be used to supply
  target group related configuration for such use cases.
  EOT
  type = list(object({
    target_group_arn = string
    container_name   = string
    container_port   = number
  }))
  default = []
}

variable "consul_ecs_config" {
  type        = any
  default     = {}
  description = <<-EOT
  Additional configuration to pass to the consul-ecs binary for the Consul gateway registration request.
  This only accepts the 'consulLogin' field the consul-ecs config file (https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json).
  EOT

  validation {
    error_message = "Only 'consulLogin' field is allowed in consul_ecs_config."
    condition = alltrue([
      for key in keys(var.consul_ecs_config) :
      contains(["consulLogin"], key)
    ])
  }

  validation {
    error_message = "Only the 'enabled', 'method', 'includeEntity', 'meta', 'region', 'stsEndpoint', and 'serverIdHeaderValue' fields are allowed in consul_ecs_config.consulLogin."
    condition = alltrue(flatten([
      for login in [lookup(var.consul_ecs_config, "consulLogin", {})] : [
        for key in keys(login) :
        contains([
          "enabled",
          "method",
          "includeEntity",
          "meta",
          "region",
          "stsEndpoint",
          "serverIdHeaderValue",
        ], key)
      ]
    ]))
  }

}

variable "http_config" {
  type        = any
  default     = {}
  description = <<-EOT
  This accepts HTTP specific TLS configuration based on the `consulServers.http` schema present in https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json.
  If unset, values of `var.tls` and `var.tls_server_name` will be used to configure TLS settings for HTTP. The HTTP port defaults to 8500 if TLS is not enabled
  or 8501 if TLS is enabled.
  EOT

  validation {
    error_message = "Only the 'port', 'https', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in http_config."
    condition = alltrue([
      for key in keys(var.http_config) :
      contains(["port", "https", "tls", "tlsServerName", "caCertFile"], key)
    ])
  }
}

variable "grpc_config" {
  type        = any
  default     = {}
  description = <<-EOT
  This accepts gRPC specific TLS configuration based on the `consulServers.grpc` schema present in https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json.
  If unset, values of `var.tls` and `var.tls_server_name` will be used to configure TLS settings for gRPC. The gRPC port defaults to 8502 if TLS is not enabled
  or 8503 if TLS is enabled.
  EOT

  validation {
    error_message = "Only the 'port', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in grpc_config."
    condition = alltrue([
      for key in keys(var.grpc_config) :
      contains(["port", "tls", "tlsServerName", "caCertFile"], key)
    ])
  }
}

variable "volumes" {
  description = "List of volumes to include in the aws_ecs_task_definition resource."
  type        = any
  default     = []
}

