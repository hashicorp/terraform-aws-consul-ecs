# Consul AWS ECS Modules

⚠️ **IMPORTANT:** This is a tech preview of Consul on AWS ECS. It does not yet support production workloads. ⚠️

This repo contains a set of modules for deploying Consul Service Mesh on
AWS ECS (Elastic Container Service).

## Documentation

See https://www.consul.io/docs/ecs for full documentation.

## Architecture
![Architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/architecture.png?raw=true)

Each task is created via the `mesh-task` module. This module adds
additional containers known as sidecar containers to your task definition.

Specifically, it adds the following containers:

* `discover-servers` – Runs at startup to discover the IP address of the Consul server.
* `mesh-init` – Runs at startup to set up initial configuration for Consul and Envoy.
* `consul-client` – Runs for the full lifecycle of the task. This container runs a
  [Consul client](https://www.consul.io/docs/architecture) that connects with
  Consul servers and configures the sidecar proxy.
* `sidecar-proxy` – Runs for the full lifecycle of the task. This container runs
  [Envoy](https://www.envoyproxy.io/) which is used to proxy and control
  service mesh traffic. All requests to and from the application run through
  the sidecar proxy.

The `dev-server` module runs a development/testing-only Consul server as an
ECS task.

## Usage

See https://www.consul.io/docs/ecs.

## Modules 

* [mesh-task](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/mesh-task): This module creates an [ECS Task Definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
  that adds additional containers to your application task, so it can be part of the Consul service mesh.

* [dev-server](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/dev-server) [**For Development/Testing Only**]: This module deploys a Consul server onto your ECS Cluster
  for development/testing purposes. The server does not have persistent storage and so is not suitable for production deployments.

## Roadmap

- [ ] Support for running Consul servers in HashiCorp Cloud Platform

## License

This code is released under the Mozilla Public License 2.0. Please see [LICENSE](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/LICENSE) for more details.
