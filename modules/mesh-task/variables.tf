variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This name will also be used as the Consul service name."
  type        = string
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
  default     = "docker.mirror.hashicorp.services/hashicorp/consul:1.9.5"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorp/consul-ecs:0.1.2"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "docker.mirror.hashicorp.services/envoyproxy/envoy-alpine:v1.16.2"
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

variable "retry_join" {
  description = "Argument to pass to -retry-join (https://www.consul.io/docs/agent/options#_retry_join). This or consul_server_service_name must be set."
  type        = string
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
