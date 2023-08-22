# Consul AWS ECS Modules

This repo contains a set of modules for deploying Consul Service Mesh on
AWS ECS (Elastic Container Service).

## Documentation

See https://developer.hashicorp.com/consul/docs/ecs for full documentation.

## Architecture

![Architecture](./_docs/architecture.png?raw=true)

Each task is created via the `mesh-task` module. This module adds
additional containers known as sidecar containers to your task definition.

Specifically, it adds the following containers:

* `consul-ecs-control-plane` – Runs for the full lifecycle of the task.
  * At startup it connects to the available Consul servers and performs a login with the configured IAM Auth method to obtain an ACL token with appropriate privileges.
  * Using the token, it registers the service and proxy entities to Consul's catalog.
  * It then bootstraps the configuration JSON required by the Consul dataplane container and writes it to a shared volume.
  * After this, the container enters into its reconciliation loop where it periodically syncs the health of ECS containers into Consul.
  * Upon receiving SIGTERM, it marks the corresponding service instance in Consul as unhealthy and waits for the dataplane container to shutdown.
  * Finally, it deregisters the service and proxy entities from Consul's catalog and performs a Consul logout.
* `consul-dataplane` – Runs for the full lifecycle of the task. This container runs
  the [Consul dataplane](https://github.com/hashicorp/consul-dataplane) that configures and starts the Envoy proxy, which controls all the service mesh traffic. All requests to and from the application run through
  the proxy.

The `ecs-controller` module runs a controller that automatically provisions ACL tokens
for tasks on the mesh. It also deregisters service instances from Consul for missing/finished tasks in ECS.

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

* [ecs-controller](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/modules/ecs-controller): This modules deploys a controller that automatically provisions ACL tokens
  for services on the Consul service mesh. It also keeps an eye on the tasks and deregisters the service instances of those tasks that go missing or get finished.

## Roadmap

Please refer to our roadmap [here](https://github.com/hashicorp/consul-ecs/projects/1).

## License

This code is released under the Mozilla Public License 2.0. Please see [LICENSE](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/LICENSE) for more details.
