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
