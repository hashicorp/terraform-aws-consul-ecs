## Unreleased
BREAKING CHANGES
* modules/mesh-task: `execution_role_arn` and `task_role_arn` variables have been removed.
  The mesh-task now creates those roles and instead accepts `additional_task_role_policies`
  and `additional_execution_role_policies` to modify the execution and task roles and allow
  more permissions. [[GH-19](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/19)]
* modules/mesh-task: `retry_join` is now a required variable and `consul_server_service_name`
  has been removed because we're now using AWS CloudMap to discover the dev server instead of
  the `discover-servers` container. [[GH-24](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/24)]

FEATURES
* Enable TLS for the Consul service mesh control plane. [[GH-19](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/19)]

IMPROVEMENTS
* Use AWS CloudMap to discover the dev server instead running the `discover-servers` container.
  [[GH-24](https://github.com/hashicorp/terraform-aws-consul-ecs/pull/24)]

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
