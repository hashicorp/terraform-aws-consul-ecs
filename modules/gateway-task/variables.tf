variable "family" {
  description = "Task definition family (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#family). This is used by default as the Consul service name if `consul_service_name` is not provided."
  type        = string
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
  default     = "public.ecr.aws/hashicorp/consul:1.12.2"
}

variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.5.0"
}

variable "envoy_image" {
  description = "Envoy Docker image."
  type        = string
  default     = "envoyproxy/envoy-alpine:v1.21.4"
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
  description = "Whether or not to enable ACL token replication. ACL token replication is required when the gateway-task is part of a WAN-federated Consul service mesh."
  default     = false
}

variable "consul_datacenter" {
  type        = string
  description = "The name of the Consul datacenter the client belongs to."
  default     = "dc1"
}

variable "consul_primary_datacenter" {
  type        = string
  description = "The name of the primary Consul datacenter. Required when the gateway-task is part of a WAN-federated Consul service mesh."
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
  description = "Subnets IDs where the gateway task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
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
