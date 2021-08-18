variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "ishustava/consul-ecs-dev:acl-test"
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the controller will be running."
  type        = string
}

variable "region" {
  description = "AWS region of the ECS cluster."
  type        = string
}

variable "consul_bootstrap_token_secret_arn" {
  description = "The ARN of the AWS SecretsManager secret containing the token to be used by this controller. The token needs to have at least 'acl:write' privileges in Consul."
  type        = string
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "subnets" {
  description = "Subnets where the controller task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
  type        = list(string)
}

variable "consul_server_http_addr" {
  description = "The HTTP(S) address of the Consul server. This must be a full URL, including port and scheme, e.g. https://consul.example.com:8501."
  type        = string
}

variable "secret_name_prefix" {
  description = "The prefix that will be used for all secret names created by this module. Must be non-empty."
  type        = string
}

variable "consul_server_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate."
  type        = string
  default     = ""
}