# Consul AWS ECS Modules

This repo contains a set of modules for deploying Consul Service Mesh on
AWS ECS (Elastic Container Service).

## Documentation

See https://www.consul.io/docs/ecs for full documentation.

## Architecture

![Architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/architecture.png?raw=true)

Each task is created via the `mesh-task` module. This module adds
additional containers known as sidecar containers to your task definition.

Specifically, it adds the following containers:

* `consul-ecs-control-plane` – Runs for the full lifecycle of the task. This
  container sets up initial configuration for Consul and Envoy,
  and syncs health checks from ECS into Consul.
* `sidecar-proxy` – Runs for the full lifecycle of the task. This container runs
  [Envoy](https://www.envoyproxy.io/) which is used to proxy and control
  service mesh traffic. All requests to and from the application run through
  the sidecar proxy.

The `controller` module runs a controller that automatically provisions ACL tokens
for tasks on the mesh.

The `dev-server` module runs a development/testing-only Consul server as an
ECS task.

Please see our [Architecture](https://www.consul.io/docs/ecs/architecture) docs for more details.

## Usage

See https://www.consul.io/docs/ecs.

## Modules

* [mesh-task](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/mesh-task): This module creates an [ECS Task Definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
  that adds additional containers to your application task, so it can be part of the Consul service mesh.

* [dev-server](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/dev-server) [**For Development/Testing Only**]: This module deploys a Consul server onto your ECS Cluster
  for development/testing purposes. The server does not have persistent storage and so is not suitable for production deployments.

* [controller](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/controller): This modules deploys a controller that automatically provisions ACL tokens
  for services on the Consul service mesh.

## Roadmap

Please refer to our roadmap [here](https://github.com/hashicorp/consul-ecs/projects/1).

## License

This code is released under the Mozilla Public License 2.0. Please see [LICENSE](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/LICENSE) for more details.
