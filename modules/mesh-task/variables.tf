variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family)."
  type        = string
}

variable "execution_role_arn" {
  description = "ARN for task execution role."
  type        = string
}

variable "task_role_arn" {
  description = "ARN for task role."
  type        = string
}

variable "port" {
  description = "Port that application listens on. If application does not listen on a port, set outbound_only to true."
  type        = number
  default     = 0
}

variable "outbound_only" {
  description = "Whether application only makes outward calls and so doesn't listen on a port."
  type        = bool
  default     = false
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "docker.io/hashicorp/consul:1.9.5"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "ghcr.io/lkysow/consul-ecs:apr27-2"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "container_definitions" {
  description = "Application container definitions (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definitions)."
  type        = list(any)
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

variable "consul_server_service_name" {
  description = "Name of Consul server ECS service when using dev server."
  type        = string
  default     = ""
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "docker.io/envoyproxy/envoy-alpine:v1.16.2"
}

variable "dev_server_enabled" {
  description = "Whether the Consul dev server running on ECS is enabled."
  type        = bool
  default     = true
}

variable "retry_join" {
  description = "Argument to pass to -retry-join. If dev_server_enabled=true don't set this, otherwise it's required (https://www.consul.io/docs/agent/options#_retry_join)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
