# Consul AWS ECS Modules

⚠️ **IMPORTANT:** This is a tech preview of Consul on AWS ECS. It does not yet support production workloads. ⚠️

This repo contains a set of modules for deploying Consul Service Mesh on
AWS ECS (Elastic Container Service) using Terraform.

## Usage



## Modules 

* [mesh-task](modules/mesh-task): This module creates an [ECS Task Definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
  that adds the necessary configuration for your application task to be part of the Consul service mesh.

* [dev-server](modules/dev-server) [**For Development/Demo Only**]: This module deploys a Consul server onto your ECS Cluster
  for development/demo purposes. The server does not have persistent storage and so is not suitable for production deployments.
  
  When you're ready to run Consul in production, you should run the Consul server via HashiCorp Cloud Platform or on EC2 VMs.
  **Note:** HashiCorp Cloud Platform is not yet supported.

## Roadmap

- [ ] Support for running Consul servers in HashiCorp Cloud Platform

## License

This code is released under the Mozilla Public License 2.0. Please see [LICENSE](LICENSE) for more details.
