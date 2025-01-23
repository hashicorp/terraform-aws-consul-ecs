# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "ecs_cluster_arn" {
  description = "ARN of pre-existing ECS cluster."
  type        = string
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

variable "subnet_ids" {
  description = "Subnet IDs into which the task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
  type        = list(string)
}

variable "lb_enabled" {
  description = "Whether to create an ALB for the server task. Useful for accessing the UI."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "The ID of the VPC."
  type        = string
}

variable "lb_subnets" {
  description = "Subnet IDs to attach to the load balancer. NOTE: These must be public subnets if you wish to access the load balancer externally."
  type        = list(string)
  default     = null
}

variable "lb_ingress_rule_cidr_blocks" {
  description = "CIDR blocks that are allowed access to the load balancer."
  type        = list(string)
  default     = null
}

variable "lb_ingress_rule_security_groups" {
  description = "Security groups that are allowed access to the load balancer."
  type        = list(string)
  default     = null
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "hashicorppreview/consul:1.20.2"
}

variable "consul_license" {
  description = "A Consul Enterprise license key. Requires consul_image to be set to a Consul Enterprise image."
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "server"
}

variable "service_discovery_namespace" {
  description = "The namespace where the Consul server service will be registered with AWS Cloud Map. Defaults to the Consul server domain name: server.<datacenter>.<domain>."
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "launch_type" {
  description = "Launch type on which to run service. Valid values are EC2 and FARGATE."
  type        = string
  default     = "EC2"
}

variable "assign_public_ip" {
  description = "Assign a public IP address to the ENI. If running in public subnets this is required so that ECS can pull the Docker images."
  type        = bool
  default     = false
}

variable "tls" {
  description = "Whether to enable TLS on the server for the control plane traffic."
  type        = bool
  default     = false
}

variable "generate_ca" {
  description = "Controls whether or not a CA key and certificate will automatically be created and stored in Secrets Manager. Default is true. Set this to false and set ca_cert_arn and ca_key_arn to provide pre-existing secrets."
  type        = bool
  default     = true
}

variable "ca_cert_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate."
  type        = string
  default     = ""
}

variable "ca_key_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate key."
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs on the server."
  type        = bool
  default     = false
}

variable "generate_bootstrap_token" {
  description = "Whether to automatically generate a bootstrap token."
  type        = bool
  default     = true
}

variable "bootstrap_token" {
  description = "The Consul bootstrap token. By default a bootstrap token will be generated automatically. This field can be used to explicity set the value of the bootstrap token."
  type        = string
  default     = ""
}

variable "bootstrap_token_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul bootstrap token. By default a secret will be created automatically."
  type        = string
  default     = ""
}

variable "wait_for_steady_state" {
  description = "Set wait_for_steady_state on the ECS service. This causes Terraform to wait for the Consul server task to be deployed."
  type        = bool
  default     = false
}

variable "datacenter" {
  description = "Consul datacenter. Defaults to 'dc1'."
  type        = string
  default     = "dc1"
}

variable "node_name" {
  description = "Node name of the Consul server. Defaults to the value of 'var.name'."
  type        = string
  default     = ""
}

variable "primary_datacenter" {
  description = "Consul primary datacenter. Required when joining Consul datacenters via mesh gateways. All datacenters are required to use the same primary datacenter."
  type        = string
  default     = ""
}

variable "retry_join_wan" {
  description = "List of WAN addresses to join for Consul WAN federation. Must not be provided when using mesh-gateway WAN federation."
  type        = list(string)
  default     = []
}

variable "primary_gateways" {
  description = "List of WAN addresses of the primary mesh gateways for Consul servers in secondary datacenters to use to reach the Consul servers in the primary datcenter."
  type        = list(string)
  default     = []
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federations via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "enable_cluster_peering" {
  description = "Controls whether or not cluster peering is enabled. Default is false."
  type        = bool
  default     = false
}

variable "additional_dns_names" {
  description = "List of additional DNS names to add to the Subject Alternative Name (SAN) field of the server's certificate."
  type        = list(string)
  default     = []
}

variable "replication_token" {
  description = "Replication token required for ACL replication in secondary datacenters. See https://www.consul.io/docs/security/acl/acl-federated-datacenters."
  type        = string
  default     = ""
}

locals {
  retry_join_wan_xor_primary_gateways = length(var.retry_join_wan) > 0 && length(var.primary_gateways) > 0 ? file("ERROR: Only one of retry_join_wan or primary_gateways may be provided.") : null
}

variable "consul_server_startup_timeout" {
  description = "The number of seconds to wait for the Consul server to become available via its ALB before continuing. The default is 300s (5m), which should be enough in most cases."
  type        = number
  default     = 300
}
