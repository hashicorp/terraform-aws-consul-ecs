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
