# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). The lower-cased family name is used by default as the Consul service name if `consul_service_name` is not provided."
  type        = string
}

variable "consul_service_name" {
  description = "The name the service will be registered as in Consul. Defaults to the Task family name."
  type        = string
  default     = ""

  validation {
    error_message = "The consul_service_name must be lower case. It must match the regex, '^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$'."
    condition     = var.consul_service_name == "" || can(regex("^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$", var.consul_service_name))
  }
}

variable "consul_service_tags" {
  description = "A list of tags included in the Consul service registration."
  type        = list(string)
  default     = []
}

variable "consul_service_meta" {
  description = "A map of metadata that will be used for the Consul service registration"
  type        = map(string)
  default     = {}
}

variable "consul_namespace" {
  description = "The Consul namespace to use to register this service [Consul Enterprise]."
  type        = string
  default     = ""
}

variable "consul_partition" {
  description = "The Consul admin partition to use to register this service [Consul Enterprise]."
  type        = string
  default     = ""
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task."
  type        = list(string)
  default     = ["EC2", "FARGATE"]
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

variable "volumes" {
  description = "List of volumes to include in the aws_ecs_task_definition resource."
  type        = any
  default     = []
}

variable "create_task_role" {
  description = "Whether mesh-task will create the task IAM role. Defaults to true. This must be set to false when passing in an existing role using the `task_role` variable."
  type        = bool
  default     = true
}

variable "task_role" {
  description = "ECS task role to include in the task definition. You must also set `create_task_role=false` so that mesh-task knows not to create a role for you. When ACLs are enabled and the AWS IAM auth method is used, the task role must be correctly configured with an `iam:GetRole` permission to fetch itself, and must be tagged with a `consul.hashicorp.com.service-name` tag containing the Consul service name and a `consul.hashicorp.com.namespace` tag containing the Consul Enterprise namespace (if applicable)."
  type = object({
    id  = string
    arn = string
  })
  default = {
    id  = null
    arn = null
  }
}

variable "create_execution_role" {
  description = "Whether mesh-task will create the execution IAM role. Defaults to true. This must be set to false when passing in an existing role using the `execution_role` variable."
  type        = bool
  default     = true
}

variable "execution_role" {
  description = "ECS execution role to include in the task definition. You must also set `create_execution_role=false` so that mesh-task knows not to create a role for you."
  type = object({
    id  = string
    arn = string
  })
  default = {
    id  = null
    arn = null
  }
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

variable "skip_server_watch" {
  description = "Set this to true to prevent the consul-dataplane and consul-ecs-control-plane from watching the Consul servers for changes. This is useful for situations where Consul servers are behind a load balancer."
  type        = bool
  default     = false
}

variable "port" {
  description = "Port that the application listens on. If the application does not listen on a port, set outbound_only to true."
  type        = number
  default     = 0
}

variable "outbound_only" {
  description = "Whether the application only makes outward requests and does not receive any requests. Must be set to true if port is 0."
  type        = bool
  default     = false
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "hashicorppreview/consul-ecs:0.7.1-dev"
}

variable "consul_dataplane_image" {
  description = "consul-dataplane Docker image."
  type        = string
  default     = "hashicorp/consul-dataplane:1.3.0"
}

variable "envoy_public_listener_port" {
  description = "The public listener port for Envoy that is used for service-to-service communication."
  type        = number
  default     = 20000

  validation {
    error_message = "The envoy_public_listener_port must be greater than 0 and less than or equal to 65535."
    condition     = var.envoy_public_listener_port > 0 && var.envoy_public_listener_port <= 65535
  }

  validation {
    error_message = "The envoy_public_listener_port must not conflict with the following ports that are reserved for Consul and Envoy: 8300, 8301, 8302, 8500, 8501, 8502, 8600, 10000, 19000."
    condition = !contains([
      8600,  // consul dns
      10000, // consul-ecs-control-plane health check port
      19000, // envoy admin port
    ], var.envoy_public_listener_port)
  }
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
      10000, // consul-ecs-control-plane health check port
      19000, // envoy admin port
    ], var.envoy_readiness_port)
  }
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = {}
}

variable "container_definitions" {
  description = "Application container definitions (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definitions)."
  # This is `any` on purpose. Using `list(any)` is too restrictive. It requires maps in the list to have the same key set, and same value types.
  type = any
}

variable "consul_server_hosts" {
  description = "Address of the Consul servers. This can be an IP address, a DNS name, or an `exec=` string specifying a script that outputs IP addresses. Refer to https://github.com/hashicorp/go-netaddrs#summary for details. This variable should not specify the port. Instead, use var.http_config.port and var.grpc_config.port to change the server HTTP and gRPC ports."
  type        = string
}

variable "upstreams" {
  description = <<-EOT
  Upstream services that this service will call. This follows the schema of the `proxy.upstreams` field of the
  consul-ecs config file (https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json).
  EOT

  type    = any
  default = []

  validation {
    error_message = "Upstream fields 'destinationName' and 'localBindPort' are required."
    condition = alltrue(flatten([
      for upstream in var.upstreams : [
        can(lookup(upstream, "destinationName")),
        can(lookup(upstream, "localBindPort")),
      ]
    ]))
  }

  validation {
    error_message = "Upstream fields must be one of 'destinationType', 'destinationNamespace', 'destinationPartition', 'destinationName', 'datacenter', 'localBindAddress', 'localBindPort', 'config', or 'meshGateway'."
    condition = alltrue(flatten([
      for upstream in var.upstreams : [
        for key in keys(upstream) : contains(
          [
            "destinationType",
            "destinationNamespace",
            "destinationPartition",
            "destinationName",
            "destinationPeer",
            "datacenter",
            "localBindAddress",
            "localBindPort",
            "config",
            "meshGateway",
          ],
          key
        )
      ]
    ]))
  }
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
  description = "Whether to enable TLS for the communication between mesh-task and Consul's HTTP and gRPC interfaces."
  type        = bool
  default     = false
}

variable "tls_server_name" {
  description = "The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces. This is the default value used when grpc_config.tlsServerName or http_config.tlsServerName is unset."
  type        = string
  default     = ""
}

variable "ca_cert_file" {
  description = <<-EOT
  The CA certificate file for Consul's internal HTTP and gRPC interfaces. `CONSUL_HTTPS_CACERT_PEM` and 
  `CONSUL_GRPC_CACERT_PEM` takes a higher precedence when configuring TLS settings in the mesh-task."
  EOT
  type        = string
  default     = ""
}

variable "consul_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces."
  type        = string
  default     = ""
}

variable "consul_grpc_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides var.consul_ca_cert_arn"
  type        = string
  default     = ""
}

variable "consul_https_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides var.consul_ca_cert_arn"
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs for the mesh task."
  type        = bool
  default     = false
}

variable "application_shutdown_delay_seconds" {
  type        = number
  description = <<-EOT
  An optional number of seconds by which to delay application shutdown. By default, there is no delay. This delay allows
  incoming traffic to drain off before your application container exits. This delays the TERM signal from ECS when
  the task is stopped. However, the KILL signal from ECS cannot be delayed, so this value should be shorter than the
  `stopTimeout` on the container definition. This works by setting an explicit `entryPoint` field on each container without an
  `entryPoint` field. Containers with a non-null `entryPoint` field will be ignored. Since this sets an explicit entrypoint,
  the default entrypoint from the image (if present) will not be used, so you may need to set the `command` field on the
  container definition to ensure your container starts properly, depending on your image.
  EOT
  default     = 0
}

variable "consul_ecs_config" {
  type        = any
  default     = {}
  description = <<-EOT
  Additional configuration to pass to the consul-ecs binary for Consul service and sidecar proxy registration requests.
  This accepts a subset of the consul-ecs config file (https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json).
  For the remainder of the consul-ecs config file contents, use the variables `upstreams`, `consul_service_name`,
  `consul_service_tags`, `consul_service_meta`, `consul_namespace`, and `consul_partition`.
  In most cases, these separate variables will suffice.
  EOT

  validation {
    error_message = "Only the 'service', 'proxy', and 'consulLogin' fields are allowed in consul_ecs_config."
    condition = alltrue([
      for key in keys(var.consul_ecs_config) :
      contains(["service", "proxy", "consulLogin"], key)
    ])
  }

  validation {
    error_message = "Only the 'enableTagOverride' and 'weights' fields are allowed in consul_ecs_config.service."
    condition = alltrue([
      for key in keys(lookup(var.consul_ecs_config, "service", {})) :
      contains(["enableTagOverride", "weights"], key)
    ])
  }

  validation {
    error_message = "Only the 'meshGateway', 'expose', and 'config' fields are allowed in consul_ecs_config.proxy."
    condition = alltrue([
      for key in keys(lookup(var.consul_ecs_config, "proxy", {})) :
      contains(["meshGateway", "expose", "config"], key)
    ])
  }

  validation {
    error_message = "Only the 'passing' and 'warning' fields are allowed in consul_ecs_config.service.weights."
    condition = alltrue(flatten([
      for service in [lookup(var.consul_ecs_config, "service", {})] : [
        for key in keys(lookup(service, "weights", {})) :
        contains(["passing", "warning"], key)
      ]
    ]))
  }

  validation {
    error_message = "Only the 'mode' field is allowed in consul_ecs_config.proxy.meshGateway."
    condition = alltrue(flatten([
      for proxy in [lookup(var.consul_ecs_config, "proxy", {})] : [
        for key in keys(lookup(proxy, "meshGateway", {})) :
        contains(["mode"], key)
      ]
    ]))
  }

  validation {
    error_message = "Only the 'checks' and 'paths' fields are allowed in consul_ecs_config.proxy.expose."
    condition = alltrue(flatten([
      for proxy in [lookup(var.consul_ecs_config, "proxy", {})] : [
        for key in keys(lookup(proxy, "expose", {})) :
        contains(["checks", "paths"], key)
      ]
    ]))
  }

  validation {
    error_message = "Only the 'listenerPort', 'path', 'localPathPort', and 'protocol' fields are allowed in each item of consul_ecs_config.proxy.expose.paths[*]."
    condition = alltrue(flatten([
      for proxy in [lookup(var.consul_ecs_config, "proxy", {})] : [
        for expose in [lookup(proxy, "expose", {})] : [
          for path in lookup(expose, "paths", []) : [
            for key in keys(path) :
            contains(["listenerPort", "path", "localPathPort", "protocol"], key)
          ]
        ]
      ]
    ]))
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
  If unset, values of `var.tls`, `var.tls_server_name` and `var.ca_cert_file` will be used to configure TLS settings for HTTP. The HTTP port defaults to 8500 if TLS is 
  not enabled or 8501 if TLS is enabled.
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
  If unset, values of `var.tls`, `var.tls_server_name` and `var.ca_cert_file` will be used to configure TLS settings for gRPC. The gRPC port defaults to 8502 if TLS is
  not enabled or 8503 if TLS is enabled.
  EOT

  validation {
    error_message = "Only the 'port', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in grpc_config."
    condition = alltrue([
      for key in keys(var.grpc_config) :
      contains(["port", "tls", "tlsServerName", "caCertFile"], key)
    ])
  }
}