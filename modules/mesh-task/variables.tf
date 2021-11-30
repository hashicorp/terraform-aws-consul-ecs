variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This name will also be used as the Consul service name."
  type        = string
}

variable "consul_service_name" {
  description = "The name the service will be registered as in Consul. Defaults to the Task family name."
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

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul:1.10.4"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.2.0"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "envoyproxy/envoy-alpine:v1.18.4"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "container_definitions" {
  description = "Application container definitions (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definitions)."
  # This is `any` on purpose. Using `list(any)` is too restrictive. It requires maps in the list to have the same key set, and same value types.
  type = any
}

variable "upstreams" {
  description = <<-EOT
  Upstream services this service will call. In the form [{destination_name = $name, local_bind_port = $port}] where
  destination_name is the name of the upstream service and local_bind_port is the local port that this application should
  use when calling the upstream service.
  EOT

  type = list(
    object({
      destination_name = string
      local_bind_port  = number
    })
  )
  default = []
}

variable "checks" {
  description = "A list of maps defining Consul checks for this service (https://www.consul.io/api-docs/agent/check#register-check)."
  type        = list(any)
  default     = []
}

variable "retry_join" {
  description = "Arguments to pass to -retry-join (https://www.consul.io/docs/agent/options#_retry_join). This or consul_server_service_name must be set."
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
  description = "The prefix of Secrets Manager secret names created by the ACL controller. If secret prefix is provided, we assume the secrets are generated by the ACL controller and follow the '<secret_prefix>-<task-family>' naming convention."
  type        = string
  default     = ""
}

variable "consul_datacenter" {
  type        = string
  description = "The name of the Consul datacenter the client belongs to."
  default     = "dc1"
}

variable "application_shutdown_delay_seconds" {
  type        = number
  description = <<EOT
  Set an application entrypoint to delay the TERM signal from ECS for this many seconds.
  This allows time for incoming traffic to drain off before your application container exits.
  This cannot delay the KILL signal from ECS, so this delay should be shorter than the `stopTimeout`
  on the container definition.

  This will set the `entryPoint` field for each container in `container_definitions` that does not have
  an `entryPoint` field. Containers with a non-null `entryPoint` field will be ignored. Since this sets
  an explicit entrypoint, the default entrypoint from the image (if present) will not be used. You may
  need to set the `command` field on the container definition to ensure the container starts properly.
  EOT
  default     = null
}
