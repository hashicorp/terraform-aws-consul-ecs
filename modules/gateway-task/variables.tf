variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This is used by default as the Consul service name if `consul_service_name` is not provided."
  type        = string
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
  description = "The Consul namespace to use to register this gateway [Consul Enterprise]."
  type        = string
  default     = ""

  validation {
    error_message = "Gateway namespace must be 'default' or the empty string."
    condition     = var.consul_namespace == "" || var.consul_namespace == "default"
  }

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

variable "task_role" {
  description = "ECS task role to include in the task definition. If not provided, a role is created."
  type = object({
    id  = string
    arn = string
  })
  default = {
    id  = null
    arn = null
  }
}

variable "execution_role" {
  description = "ECS execution role to include in the task definition. If not provided, a role is created."
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

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul:1.12.0"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.4.1-dev"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "envoyproxy/envoy-alpine:v1.20.2"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "retry_join" {
  description = "Arguments to pass to -retry-join (https://www.consul.io/docs/agent/options#_retry_join). This or `consul_server_service_name` must be set."
  type        = list(string)
}

variable "consul_http_addr" {
  description = "Consul HTTP Address. Required when using the IAM Auth Method to obtain ACL tokens."
  type        = string
  default     = ""
}

variable "consul_https_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the CA certificate for Consul's HTTPS interface."
  type        = string
  default     = ""
}

variable "client_token_auth_method_name" {
  description = "The name of the Consul Auth Method to login to for client tokens."
  type        = string
  default     = "iam-ecs-client-token"
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
  description = "Whether to enable TLS for the mesh-task for the control plane traffic."
  type        = bool
  default     = false
}

variable "consul_server_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal RPC."
  type        = string
  default     = ""
}

variable "gossip_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul gossip encryption key."
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs for the gateway task."
  type        = bool
  default     = false
}

variable "enable_acl_token_replication" {
  type        = bool
  description = "Whether or not to enable ACL token replication for federated. ACL token replication is required when the mesh-task is part of a WAN federated Consul service mesh."
  default     = false
}

variable "consul_datacenter" {
  type        = string
  description = "The name of the Consul datacenter the client belongs to."
  default     = "dc1"
}

variable "consul_primary_datacenter" {
  type        = string
  description = "The name of the primary Consul datacenter. Required when the mesh-task is part of a WAN federated Consul service mesh."
  default     = ""
}

variable "consul_agent_configuration" {
  type        = string
  description = "The contents of a configuration file for the Consul Agent in HCL format."
  default     = ""
}

variable "kind" {
  description = "Gateway kind."
  type        = string

  validation {
    error_message = "Gateway kind must be 'mesh-gateway'."
    condition     = contains(["mesh-gateway"], var.kind)
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

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "retry_join_wan" {
  description = "List of WAN addresses to join for Consul cluster federation. Must not be provided when using mesh-gateway for WAN federation."
  type        = list(string)
  default     = []
}
