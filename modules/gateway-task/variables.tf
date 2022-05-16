variable "family" {
  description = "Task definition [family](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This is used by default as the Consul service name if `consul_service_name` is not provided."
  type        = string
}

variable "kind" {
  description = "Gateway kind."
  type        = string

  validation {
    error_message = "Gateway kind must be one of 'mesh-gateway', 'terminating-gateway', 'ingress-gateway'."
    condition     = contains(["mesh-gateway", "terminating-gateway", "ingress-gateway"], var.kind)
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
  description = "WAN port for the gateway. Defaults to 8443 if not specified."
  type        = number
  default     = 0
}

variable "consul_service_name" {
  description = "The name the gateway service will be registered as in Consul. Defaults to the Task family name. Always suffixed with the gateway kind."
  type        = string
  default     = ""
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
  default     = null
}

variable "consul_partition" {
  description = "The Consul admin partition to use to register this service [Consul Enterprise]."
  type        = string
  default     = null
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "retry_join_wan" {
  description = "List of WAN addresses to join for Consul datacenter federation. Must not be provided when using mesh-gateway federation."
  type        = list(string)
  default     = null
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

variable "task_role" {
  description = "ECS task role to include in the task definition. If not provided, a role is created."
  type = object({
    id  = string
    arn = string
  })
  default = null
}

variable "execution_role" {
  description = "ECS execution role to include in the task definition. If not provided, a role is created."
  type = object({
    id  = string
    arn = string
  })
  default = null
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
  default     = "public.ecr.aws/hashicorp/consul:1.11.2"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  // default     = "public.ecr.aws/hashicorp/consul-ecs:0.3.0"
  default = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:753e05a"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "envoyproxy/envoy-alpine:v1.20.1"
}

variable "log_configuration" {
  description = "Task definition [log configuration object](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "retry_join" {
  description = "Arguments to pass to [-retry-join](https://www.consul.io/docs/agent/options#_retry_join). This or `consul_server_service_name` must be set."
  type        = list(string)
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "tls" {
  description = "Whether to enable TLS for the mesh-task for the control plane traffic."
  type        = bool
  default     = false
}

variable "consul_server_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate."
  type        = string
  default     = ""
}

variable "gossip_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul gossip encryption key."
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs for the mesh task."
  type        = bool
  default     = false
}

variable "consul_client_token_secret_arn" {
  description = "The ARN of the Secrets Manager secret where the Consul client token is stored."
  type        = string
  default     = ""
}

variable "acl_secret_name_prefix" {
  description = "The prefix of Secrets Manager secret names created by the ACL controller. If secret prefix is provided, we assume the secrets are generated by the ACL controller and follow the `<secret_prefix>-<task-family>` naming convention."
  type        = string
  default     = ""
}

variable "consul_datacenter" {
  type        = string
  description = "The name of the Consul datacenter the client belongs to."
  default     = "dc1"
}

variable "consul_agent_configuration" {
  type        = string
  description = "The contents of a configuration file for the Consul Agent in HCL format."
  default     = null
}

variable "consul_ecs_config" {
  type        = any
  default     = {}
  description = <<EOT
  Additional configuration to pass to the consul-ecs binary for Consul service and sidecar proxy registration requests.

  This accepts a subset of the [consul-ecs config file](https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json).
  For the remainder of the consul-ecs config file contents, use the variables `upstreams`, `checks`, `consul_service_name`,
  `consul_service_tags`, `consul_service_meta`, `consul_namespace`, and `consul_partition`. In most cases, these separate variables will suffice.

  Example:
  ```
  consul_ecs_config = {
    service = {
      enableTagOverride = false
      weights = {
        passing = 1
        warning = 1
      }
    }
    proxy = {
      config = {}
      meshGateway = {
        mode = "remote"
      }
      expose = {
        checks = true
        paths = [
          {
            listenerPort = 1234
            path = "/path"
            localPathPort = 2345
            protocol = "http"
          }
        ]
      }
    }
  }
  ```
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
