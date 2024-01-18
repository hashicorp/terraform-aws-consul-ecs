## Unreleased

BREAKING CHANGES
* Following are the changes made to the task definitions for `mesh-task` and `gateway-task` submodules to react to the changes made in [this](https://github.com/hashicorp/consul-ecs/pull/211) PR.
  - Removes the `consul-ecs-control-plane` container from the task definition and adds a new `consul-ecs-mesh-init` container which will be responsible for setting up mesh on ECS.
  - Adds a new container named `consul-ecs-health-sync` to the task definition which will be responsible for syncing back ECS container health checks into Consul. This container will wait for a successful exit of `consul-ecs-mesh-init` container before starting.
* Add support for transparent proxy in ECS tasks based on EC2 launch types. This feature automatically routes outgoing/incoming traffic to/from the application container to the sidecar proxy container deployed in the same task. Following are the changes made to the `mesh-task` submodule [[GH-264](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/264)]
  - Adds the following variables [[GH-209](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/209)]
    - `enable_transparent_proxy` - Defaults to `true`. Fargate based tasks should explicitly pass `false` to avoid validation errors during terraform planning phase.
    - `enable_consul_dns` - Defaults to `false`. Indicates whether Consul DNS should be configured for this task. Enabling this makes Consul dataplane start up a proxy DNS server that forwards requests to the Consul DNS server. `var.enable_transparent_proxy` should be `true` to enable this setting.
    - `exclude_inbound_ports` - List of inbound ports to exclude from traffic redirection.
    - `exclude_outbound_ports` - List of outbound ports to exclude from traffic redirection.
    - `exclude_outbound_cidrs` - List of additional IP CIDRs to exclude from outbound traffic redirection.
    - `exclude_outbound_uids` - List of additional process UIDs to exclude from traffic redirection.
  - Adds the `CAP_NET_ADMIN` linux capability to the `mesh-init` container when `var.enable_transaparent_proxy` is set to `true`. This is needed to modify iptable rules within the ECS task.
  - `mesh-init` container is run as a `root` user.
  - Assign a UID of `5995` for the `consul-dataplane` container and `5996` for the `health-sync` container. This is done to selectively exclude the traffic flowing through these containers from the redirection rules.

FEATURES
* Add support for provisioning API gateways as ECS tasks [[GH-234](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/234)]
  - Add `api-gateway` as an acceptable `kind` input.
  - Add `custom_load_balancer_config` input variable which can be used to feed in custom load balancer target group config that can be attached to the gateway's ECS task.
  - Add `consul.hashicorp.com.gateway-kind` as a tag to the gateway task's IAM Role. This field will hold the type of the gateway that is getting deployed to the ECS task and will be used by the configured IAM auth method to mint tokens
  with appropriate permissions when individual tasks perform a Consul login.
* Add support for provisioning Terminating gateways as ECS tasks [[GH-236](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/236)]
  - Add `terminating-gateway` as an acceptable `kind` input for the gateway submodule.
* examples/api-gateway: Add example terraform to demonstrate exposing mesh tasks in ECS via Consul API gateway deployed as an ECS task. [[GH-235]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/235)
* examples/terminating-gateway: Add example terraform to demonstrate the use of terminating gateways deployed as ECS tasks to facilitate communication between mesh and non mesh services. [[GH-238]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/238)
* examples/dev-server-ec2-transparent-proxy: Add example terraform to demonstrate Consul's transparent proxy feature for services deployed in ECS EC2 launch type tasks. [[GH-265](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/265)]

## 0.7.1 (Dec 19, 2023)

IMPROVEMENTS
* Bump Consul ECS image version to 0.7.1
* Bump Consul Dataplane's image version to 1.3.1

BUG FIXES
* Fixes a bug in the health check logic of the `consul-ecs-control-plane` container in `mesh-task` and `gateway-task` submodule. Because of the bug, the ECS agent tries to start up the `consul-dataplane` container before the `consul-ecs-control-plane` container writes the Consul ECS binary to a shared volume. [[GH-241]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/241)

## 0.7.0 (Nov 8, 2023)

BREAKING CHANGES
* Adopt the architecture described in [Simplified Service Mesh with Consul Dataplane](https://developer.hashicorp.com/consul/docs/connect/dataplane) for ECS.[[GH-199]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/199)
* Following changes are made to the `mesh-task` submodule: [[GH-188]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/188)
  - Remove `consul-client` container definition from the ECS task definition.
  - Rename `mesh-init` container to `consul-ecs-control-plane` and the `mesh-init` command to `control-plane`.
  - Remove the `sidecar-proxy` container and replace it with the `consul-dataplane` container.
  - Remove the `consul-ecs-health-sync` container definition.
  - Remove the following input variables
    - `envoy_image`
    - `checks`
    - `retry_join`
    - `consul_http_addr`
    - `client_token_auth_method_name`
    - `gossip_key_secret_arn`
    - `consul_server_ca_cert_arn`
    - `consul_agent_configuration`
    - `enable_acl_token_replication`
    - `consul_datacenter`
    - `consul_primary_datacenter`
  - Add the following input variables
    - `skip_server_watch`: To prevent the consul-dataplane and consul-ecs-control-plane containers from watching the Consul servers for changes. Useful for situations where Consul servers are behind a load balancer.
    - `consul_dataplane_image`: Consul Dataplane's Docker image.
    - `envoy_readiness_port`: Port that is exposed by Envoy which can be hit to determine its readiness.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `ca_cert_file`: Path of the CA certificate file for Consul's internal HTTP and gRPC interfaces.
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `http_config`: Contains HTTP specific TLS settings.
    - `grpc_config`: Contains gRPC specific TLS settings.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
  - Add `consulServers` field to `local.config` which gets passed to the `control-plane` container.
* Rename `acl-controller` submodule to `controller`. Following are the changes made to the same: [[GH-188]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/188)
  - Rename `consul-acl-controller` container to `consul-ecs-controller`.
  - Pass the `CONSUL_ECS_CONFIG_JSON`(which contains the configuration for configuring Consul on ECS) to the `consul-ecs-controller` container similar to how it is being done in the `mesh-task` submodule.
  - Remove the following CLI flags that were getting passed to the existing command
    - `-iam-role-path`
    - `-partitions-enabled`
    - `-partition`
  - Remove the following variables
    - `consul_server_http_addr`
    - `consul_server_ca_cert_arn`
  - Add the following variables
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls`: Whether to enable TLS for the controller to Consul server traffic.
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `http_config`: Contains HTTP specific TLS settings for controller to Control plane traffic.
    - `grpc_config`: Contains gRPC specific TLS settings for controller to Control plane traffic.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
* Following changes are made to the `gateway-task` submodule: [[GH-189]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/189)
  - Remove `consul-client` container definition from the ECS task definition.
  - Rename `mesh-init` container to `consul-ecs-control-plane` and the `mesh-init` command to `control-plane`.
  - Remove the `sidecar-proxy` container and replace it with the `consul-dataplane` container.
  - Remove the `consul-ecs-health-sync` container definition.
  - Remove the following input variables
    - `envoy_image`
    - `retry_join`
    - `consul_http_addr`
    - `client_token_auth_method_name`
    - `gossip_key_secret_arn`
    - `consul_server_ca_cert_arn`
    - `consul_agent_configuration`
    - `enable_acl_token_replication`
    - `consul_datacenter`
    - `consul_primary_datacenter`
    - `audit_logging`
  - Add the following input variables
    - `skip_server_watch`: To prevent the consul-dataplane and consul-ecs-control-plane containers from watching the Consul servers for changes. Useful for situations where Consul servers are behind a load balancer.
    - `consul-dataplane-image`: Consul Dataplane's Docker image.
    - `envoy_readiness_port`: Port that is exposed by Envoy which can be hit to determine its readiness.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `http_config`: Contains HTTP specific TLS settings for the consul-ecs-control-plane to Consul server traffic.
    - `grpc_config`: Contains gRPC specific TLS settings for the consul-ecs-control-plane to Consul server traffic.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
  - Add `consulServers` field to `local.config` which gets passed to the `control-plane` container.
* Following are the changes made to `dev-server` submodule: [[GH-191]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/191)
  - Remove the following variables:
    - `gossip_encryption_enabled`
    - `generate_gossip_encryption_key`
    - `gossip_key_secret_arn`
* Add changes to the `dev-server-ec2` and `dev-server-fargate` examples to adopt the changes made to `mesh-task` submodule. [[GH-191]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/191)
* Add changes to the `mesh-gateways` example to adopt the Consul Dataplane based architeture on ECS. [[GH-192]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/192)
* Add changes to the `admin-partitions` example to adopt the Consul Dataplane based architeture on ECS. [[GH-193]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/193)


IMPROVEMENTS
* examples/cluster-peering: Add example terraform to illustrate Consul's cluster peering usecase on ECS. [[GH-194]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/194)
* examples/service-sameness: Add example terraform to illustrate Consul's service sameness group usecase on ECS. [[GH-202]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/202)
* examples/locality-aware-routing: Add example terraform to demonstrate Consul's locality aware routing feature between ECS tasks [[GH-219]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/219)

## 0.7.0-rc1 (Oct 16, 2023)

BREAKING CHANGES
* Adopt the architecture described in [Simplified Service Mesh with Consul Dataplane](https://developer.hashicorp.com/consul/docs/connect/dataplane) for ECS.[[GH-199]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/199)
* Following changes are made to the `mesh-task` submodule: [[GH-188]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/188)
  - Remove `consul-client` container definition from the ECS task definition.
  - Rename `mesh-init` container to `consul-ecs-control-plane` and the `mesh-init` command to `control-plane`.
  - Remove the `sidecar-proxy` container and replace it with the `consul-dataplane` container.
  - Remove the `consul-ecs-health-sync` container definition.
  - Remove the following input variables
    - `envoy_image`
    - `checks`
    - `retry_join`
    - `consul_http_addr`
    - `client_token_auth_method_name`
    - `gossip_key_secret_arn`
    - `consul_server_ca_cert_arn`
    - `consul_agent_configuration`
    - `enable_acl_token_replication`
    - `consul_datacenter`
    - `consul_primary_datacenter`
  - Add the following input variables
    - `skip_server_watch`: To prevent the consul-dataplane and consul-ecs-control-plane containers from watching the Consul servers for changes. Useful for situations where Consul servers are behind a load balancer.
    - `consul_dataplane_image`: Consul Dataplane's Docker image.
    - `envoy_readiness_port`: Port that is exposed by Envoy which can be hit to determine its readiness.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `ca_cert_file`: Path of the CA certificate file for Consul's internal HTTP and gRPC interfaces.
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `http_config`: Contains HTTP specific TLS settings.
    - `grpc_config`: Contains gRPC specific TLS settings.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
  - Add `consulServers` field to `local.config` which gets passed to the `control-plane` container.
* Rename `acl-controller` submodule to `controller`. Following are the changes made to the same: [[GH-188]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/188)
  - Rename `consul-acl-controller` container to `consul-ecs-controller`.
  - Pass the `CONSUL_ECS_CONFIG_JSON`(which contains the configuration for configuring Consul on ECS) to the `consul-ecs-controller` container similar to how it is being done in the `mesh-task` submodule.
  - Remove the following CLI flags that were getting passed to the existing command
    - `-iam-role-path`
    - `-partitions-enabled`
    - `-partition`
  - Remove the following variables
    - `consul_server_http_addr`
    - `consul_server_ca_cert_arn`
  - Add the following variables
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls`: Whether to enable TLS for the controller to Consul server traffic.
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `http_config`: Contains HTTP specific TLS settings for controller to Control plane traffic.
    - `grpc_config`: Contains gRPC specific TLS settings for controller to Control plane traffic.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
* Following changes are made to the `gateway-task` submodule: [[GH-189]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/189)
  - Remove `consul-client` container definition from the ECS task definition.
  - Rename `mesh-init` container to `consul-ecs-control-plane` and the `mesh-init` command to `control-plane`.
  - Remove the `sidecar-proxy` container and replace it with the `consul-dataplane` container.
  - Remove the `consul-ecs-health-sync` container definition.
  - Remove the following input variables
    - `envoy_image`
    - `retry_join`
    - `consul_http_addr`
    - `client_token_auth_method_name`
    - `gossip_key_secret_arn`
    - `consul_server_ca_cert_arn`
    - `consul_agent_configuration`
    - `enable_acl_token_replication`
    - `consul_datacenter`
    - `consul_primary_datacenter`
    - `audit_logging`
  - Add the following input variables
    - `skip_server_watch`: To prevent the consul-dataplane and consul-ecs-control-plane containers from watching the Consul servers for changes. Useful for situations where Consul servers are behind a load balancer.
    - `consul-dataplane-image`: Consul Dataplane's Docker image.
    - `envoy_readiness_port`: Port that is exposed by Envoy which can be hit to determine its readiness.
    - `consul_server_hosts`: Address of Consul servers. Can be an IP, DNS name or an `exec=` string specifying the script that outputs IP address(es).
    - `tls_server_name`: The server name to use as the SNI host when connecting via TLS to Consul's HTTP and gRPC interfaces.
    - `consul_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC and HTTP interfaces.
    - `consul_grpc_ca_cert_arn`: ARN of the Secrets Manager secret containing the Consul server CA certificate for Consul's internal gRPC communications. Overrides `var.consul_ca_cert_arn`.
    - `consul_https_ca_cert_arn`: ARN of the Secrets Manager secret containing the CA certificate for Consul server's HTTP interface. Overrides `var.consul_ca_cert_arn`.
    - `http_config`: Contains HTTP specific TLS settings for the consul-ecs-control-plane to Consul server traffic.
    - `grpc_config`: Contains gRPC specific TLS settings for the consul-ecs-control-plane to Consul server traffic.
  - Add IAM policies to fetch `consul_ca_cert_arn`, `consul_grpc_ca_cert_arn` and `consul_https_ca_cert_arn` from Secrets manager.
  - Add `consulServers` field to `local.config` which gets passed to the `control-plane` container.
* Following are the changes made to `dev-server` submodule: [[GH-191]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/191)
  - Remove the following variables:
    - `gossip_encryption_enabled`
    - `generate_gossip_encryption_key`
    - `gossip_key_secret_arn`
* Add changes to the `dev-server-ec2` and `dev-server-fargate` examples to adopt the changes made to `mesh-task` submodule. [[GH-191]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/191)
* Add changes to the `mesh-gateways` example to adopt the Consul Dataplane based architeture on ECS. [[GH-192]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/192)
* Add changes to the `admin-partitions` example to adopt the Consul Dataplane based architeture on ECS. [[GH-193]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/193)


IMPROVEMENTS
* examples/cluster-peering: Add example terraform to illustrate Consul's cluster peering usecase on ECS. [[GH-194]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/194)
* examples/service-sameness: Add example terraform to illustrate Consul's service sameness group usecase on ECS. [[GH-202]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/202)
* examples/locality-aware-routing: Add example terraform to demonstrate Consul's locality aware routing feature between ECS tasks [[GH-219]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/219)


## 0.6.1 (Jul 20, 2023)

IMPROVEMENTS
* Bump Consul OSS image version to 1.15.4 and Consul enterprise version to 1.15.4-ent
* Bump envoy image to 1.23.10

## 0.6.0 (Mar 15, 2023)

FEATURES
* modules/gateway-task: Use `consul-ecs envoy-entrypoint` to start the Envoy process for gateway tasks.
  [[GH-162]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/162)
* modules/mesh-task and modules/gateway-task: Add support for Consul 1.15.x.
  [[GH-159]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/159)
* modules/mesh-task: Add `envoy_public_listener_port` variable to set Envoy's public listener port.
* modules/acl-controller: Add `additional_execution_role_policies` variable to support attaching custom policies to the task's execution role.
* modules/mesh-task: Improve the logic behind the `defaulted_check_containers` local creation in order to prevent enabling health checks when
  the task definition passed in `var.container_definitions` has the `healthCheck` set to `null`.
  [[GH-153]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/153)

IMPROVEMENTS
* module/acl-controller: Restrict container access (read-only) to root file system.
  [[GH-158](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/158)]

## 0.5.1 (July 29, 2022)

FEATURES
* modules/mesh-task and modules/gateway-task: Add `audit_logging` flag to support audit logging for Consul Enterprise.
  [[GH-128]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/128)

BUG FIXES
* modules/dev-server: Fix a bug where the `dev-server` selects the wrong gossip encryption key
  secret ARN when creating the execution policy. The gossip encryption key selection would work
  if the secret ARN was passed in, but it would fail when trying to use the generated gossip key.
  The cause of the failure was an incorrect resource ARN in the generated policy.
  [[GH-133](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/133)]

## 0.5.0 (June 21, 2022)

BREAKING CHANGES
* modules/mesh-task: Add `create_task_role` and `create_execution_role` flags to mesh-task. When
  passing existing roles using the `task_role` and `execution_role` input variables, you must also
  set `create_task_role=false` and `create_execution_role=false`, respectively, to ensure no roles
  are created and that the passed roles are used by the task definition. The `mesh-task` module
  will no longer add policies or attempt to configure roles which are passed in.
  [[GH-113]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/113)
* modules/mesh-task, modules/acl-controller: Support the Consul AWS IAM auth method. This requires
  Consul 1.12.0+. Add `consul_http_addr`, `consul_https_ca_cert_arn`, `client_token_auth_method_name`,
  `service_token_auth_method_name`, and `iam_role_path` variables to `mesh-task`. Add `iam_role_path`
  variable to `acl-controller`. Add an `iam:GetRole` permission to the task role. Set the tags
  `consul.hashicorp.com.service-name` and `consul.hashicorp.com.namespace` on the task role.
  `health-sync` runs when ACLs are enabled, in order to do a `consul logout` when the task stops.
  Remove `consul_client_token_secret_arn` and `acl_secret_name_prefix` variables from `mesh-task`.
  No longer create Secrets Manager secrets for client or service tokens.
  [[GH-100](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/100)]
  [[GH-103](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/103)]
  [[GH-107](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/107)]
* modules/mesh-task: A lower case service name is required. When the `consul_service_name` field is
  specified, it must be a valid name for a Consul service identity. Otherwise, if `consul_service_name`
  is not specified, the lower-cased task family is used for the Consul service name.
  [[GH-109](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/109)]

FEATURES
* modules/gateway-task: Add a `health-sync` container to `gateway-task` when ACLs are enabled
  to perform a `consul logout` when the task stops.
  [[GH-120]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/120)
* modules/gateway-task: Add an optional configuration to have the `gateway-task` module
  automatically create and configure a Network Load Balancer for public ingress. Update
  the `gateway-task` module to create the ECS service definition.
  [[GH-119]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/119)
* modules/gateway-task, modules/mesh-task, modules/dev-server:
  Update `gateway-task`, `mesh-task` and `dev-server` to enable ACL token replication
  in Consul agents for WAN federation. Update `dev-server` to take a bootstrap token as
  an input.
  [[GH-116]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/116)
* modules/gateway-task, modules/dev-server:
  Add new `gateway-task` module to create mesh gateway ECS tasks that support Consul
  WAN federation via mesh gateways. Update the `dev-server` module to accept TLS
  and gossip encryption secrets so they can be passed in as variables. Modified the
  `dev-server` agent command to support WAN federation and TLS. Updated the
  `tls-init` container of the `dev-server` to create certs with SANs that
  work with CloudMap.
  [[GH-110]](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/110)
* modules/mesh-task: Update default Consul image to 1.12.0 and default Envoy image to 1.21.2.
  [[GH-114](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/114)]
* modules/dev-server: Immediately delete all Secrets Manager secrets rather
 than leaving a 30 day recovery window.
 [[GH-100](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/100)]
* modules/dev-server: Add `consul_license` input variable to support
  passing a Consul enterprise license.
  [[GH-96](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/96)]

BUG FIXES
* modules/mesh-task: Remove deprecated `key_algorithm` field. [[GH-104](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/104)]

## 0.4.2 (Jun 29, 2022)

BREAKING CHANGES
* modules/mesh-task: Add `create_task_role` and `create_execution_role` variables to mesh-task. Add
  the `service_token_secret_arn` output variable. When passing existing roles using the `task_role`
  and `execution_role` input variables, you must also set `create_task_role=false` and
  `create_execution_role=false`, respectively, to ensure no roles are created and that the passed
  roles are used by the task definition. The `mesh-task` module will no longer add policies or
  attempt to configure roles which are passed in.

## 0.4.1 (April 8, 2022)

BUG FIXES
* modules/mesh-task: Fix a bug that results in invalid secret names
  when admin partitions are enabled.
  [[GH-95](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/95)]

## 0.4.0 (April 4, 2022)

FEATURES
* Add support for Admin Partitions and Namespaces.
  [[GH-87](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/87)]

IMPROVEMENTS
* module/acl-controller: Support `security_groups` input variable.
  [[GH-89](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/89)]
* modules/mesh-task, modules/dev-server: Update default Consul image to 1.11.4
  and default Envoy image to 1.20.2.
  [[GH-93](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/93)]


## 0.3.0 (Jan 27, 2022)

BREAKING CHANGES
* modules/mesh-task: The `upstreams` and `checks` variables both require camel case
  field names to match the [consul-ecs config file](https://github.com/hashicorp/consul-ecs/blob/main/config/schema.json).
  [[GH-80](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/80)]

FEATURES
* modules/acl-controller: Add `assign_public_ip` variable to the ACL controller
  to support running on public subnets.
  [[GH-64](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/64)]
* modules/mesh-task: Add `task_role_arn` and `execution_role_arn` input variables
  which specify the task and execution role to include in the task definition.
  [[GH-71](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/71)]
* modules/mesh-task: Add `application_shutdown_delay_seconds` variable to
  delay application shutdown. This allows time for incoming traffic to drain
  off for better graceful shutdown.
  [[GH-67](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/67)]
* module/mesh-task: Additional options can be passed to the Consul service
  and sidecar proxy registration requests using the `consul_ecs_config`,
  `upstreams`, `consul_namespace`, and `consul_partition` variables.
  [[GH-80](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/80)]
  [[GH-84](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/84)]
* module/mesh-task: Add `consul_agent_configuration` variable to pass
  additional configuration to the Consul agent.
  [[GH-82](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/82)]

IMPROVEMENTS
* modules/mesh-task: Cleanup unnecessary port mappings.
  [[GH-78](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/78)]
* modules/mesh-task, modules/dev-server: Update default Consul image to 1.11.2
  and default Envoy image to 1.20.1.
  [[GH-84](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/84)]

## 0.2.0 (Nov 16, 2021)

BREAKING CHANGES
* modules/mesh-task: The `retry_join` variable was updated to take a list of
  members rather than a single member.
  [[GH-59](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/59)]

FEATURES
* modules/mesh-task: Run a `health-sync` container for essential containers when
  ECS health checks are defined and there aren't any Consul health checks
  [[GH-45](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/45)]
* modules/mesh-task: Add `consul_service_tags`, `consul_service_meta` and
  `consul_service_name` input variables to the mesh-task. When
  `consul_service_name` is unset, the ECS task family name is used for the
  Consul service name.
  [[GH-58](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/58)]

IMPROVEMENTS
* modules/mesh-task: Run the `consul-ecs-mesh-init` container with the
  `consul-ecs` user instead of `root`
  [[GH-52](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/52)]
* modules/mesh-task: The Consul binary is now inserted into
  `consul-ecs-mesh-init` from the `consul-client` container. This means that
  each release of `consul-ecs` will work with multiple Consul versions.
  [[GH-53](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/53)]
* modules/mesh-task: Keep Envoy running into Task shutdown until application containers
  have exited. This allows outgoing requests to the mesh so that applications can
  shut down gracefully. [[GH-48](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/48)]
  [[GH-61](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/61)]

BUG FIXES
* modules/acl-controller and modules/mesh-task: Fix a bug that results in
  AWS Secrets Manager secrets failing to be created.
  [[GH-63](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/63)]

## 0.2.0-beta2 (Sep 30, 2021)

FEATURES
* modules/mesh-task: Add `checks` variable to define Consul native checks.
  [[GH-41](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/41)]

## 0.2.0-beta1 (Sep 16, 2021)

BREAKING CHANGES
* modules/mesh-task: `execution_role_arn` and `task_role_arn` variables have been removed.
  The mesh-task now creates those roles and instead accepts `additional_task_role_policies`
  and `additional_execution_role_policies` to modify the execution and task roles and allow
  more permissions. [[GH-19](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/19)]
* modules/mesh-task: `retry_join` is now a required variable and `consul_server_service_name`
  has been removed because we're now using AWS CloudMap to discover the dev server instead of
  the `discover-servers` container. [[GH-24](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/24)]

FEATURES
* modules/mesh-task: Enable gossip encryption for the Consul service mesh control plane. [[GH-21](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/21)]
* modules/mesh-task: Enable TLS for the Consul service mesh control plane. [[GH-19](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/19)]
* modules/acl-controller: Add new ACL controller module and enable ACLs for other components. [[GH-31](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/31)]

IMPROVEMENTS
* modules/dev-server: Use AWS CloudMap to discover the dev server instead running the `discover-servers` container.
  [[GH-24](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/24)]
* modules/mesh-task: Increase file descriptor limit for the sidecar-proxy container.
  [[GH-34](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/34)]
* Support deployments on the ECS launch type. [[GH-25](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/25)]

BUG FIXES
* Use `ECS_CONTAINER_METADATA_URI_V4` url. [[GH-23](https://github.com/hashicorp/terraform-aws-consul-ecs/issues/23)]

## 0.1.1 (May 26, 2021)

IMPROVEMENTS
* Update Docker images to use docker.mirror.hashicorp.services mirror to avoid image pull errors.
* modules/mesh-task: Update to latest consul-ecs image (0.1.2).
* modules/mesh-task: Change containers running consul-ecs image to run as root so they can write
  to the shared /consul volume.
* modules/dev-server: Add variable `assign_public_ip` that is needed to run in public subnets. Defaults to `false`.

BREAKING CHANGES
* modules/dev-server: Add variable `launch_type` to select launch type Fargate or EC2.
  Defaults to `EC2` whereas previously it defaulted to `FARGATE`.

## 0.1.0 (May 24, 2021)

Initial release.
