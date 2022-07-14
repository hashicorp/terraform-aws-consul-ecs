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

// TODO: Remove consul-client once we're off of the Consul CLI.
variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  // This contains the 'consul connect envoy' changes we need for agentless.
  //   https://github.com/hashicorp/consul/pull/13361
  //   https://github.com/hashicorp/consul/pull/13450
  default = "docker.mirror.hashicorp.services/hashicorppreview/consul:1.13.0-dev-411edc876b4f14eb4abe2b01be882fde59c38e3c"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  // This contains my changes to do service registration and such with the Consul servers instead of the agent.
  default = "ghcr.io/pglass/consul-ecs-dev:latest"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "envoyproxy/envoy-alpine:v1.21.4"
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

variable "consul_server_hosts" {
  description = "The Consul server locations. This can be an IP address or hostname, or an exec command."
  type        = string
}

variable "consul_https_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the CA certificate for Consul's HTTPS interface."
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

variable "consul_server_https" {
  description = "Whether to use HTTPS connections to the consul_server_hosts. Defaults to true."
  type        = bool
  default     = true
}

variable "consul_server_http_port" {
  description = "The Consul server HTTP(S) port. Defaults to 8501."
  type        = number
  default     = 8501
}

variable "consul_server_grpc_port" {
  description = "The Consul server gRPC port. Defaults to 8502."
  type        = number
  default     = 8502
}

variable "acls" {
  description = "Whether to enable ACLs for the mesh task."
  type        = bool
  default     = false
}

variable "consul_datacenter" {
  type        = string
  description = "The name of the Consul datacenter the client belongs to."
  default     = "dc1"
}

// TODO: I don't think I need this for agentless.
variable "consul_primary_datacenter" {
  type        = string
  description = "The name of the primary Consul datacenter. Required when the mesh-task is part of a WAN federated Consul service mesh."
  default     = ""
}

// TODO: Enable these when adding in consul-dataplane.
//variable "consul_dataplane_image" {
//  type        = string
//  description = "The consul-dataplane image."
//  default     = "public.ecr.aws/hashicorp/consul-dataplane:FIXME_VERSION"
//}
//
//variable "consul_dataplane_environment" {
//  type        = any
//  description = "Environment variables to set in the consul-dataplane container."
//  default     = {}
//}

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
  For the remainder of the consul-ecs config file contents, use the variables `upstreams`, `checks`, `consul_service_name`,
  `consul_service_tags`, `consul_service_meta`, `consul_namespace`, and `consul_partition`.
  In most cases, these separate variables will suffice.
  EOT

  validation {
    error_message = "Only the 'service' and 'proxy' fields are allowed in consul_ecs_config."
    condition = alltrue([
      for key in keys(var.consul_ecs_config) :
      contains(["service", "proxy"], key)
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
}
