## 0.1.1 (May 24, 2021)

IMPROVEMENTS
* Update Docker images to use docker.mirror.hashicorp.services mirror to avoid image pull errors.
* Update to latest consul-ecs image (0.1.2).
* Change containers running consul-ecs image to run as root so they can write
  to the shared /consul volume.

## 0.1.0 (May 24, 2021)

Initial release.
