# Overview

This directory contains the Docker image used for our acceptance tests. The image is pre-built and
manually pushed to [`hashicorpdev/consul-ecs-test`](https://hub.docker.com/r/hashicorpdev/consul-ecs-test).

It contains the following:

- Terraform
- AWS CLI
- AWS Session Manager Plugin for `aws ecs execute-command`
- ECS CLI


# Updating the image

First, bump the `VERSION` in the Makefile. Then use the makefile to build the image:

```
make build
```

To push the image, you must first login to Docker as the `hashicorpconsul` user:

```
make push
```

After you've pushed the image, logout of the `hashicorpconsul` user.

Then, update the `.circleci/config.yml` to reference the new version of the image:

```
diff --git a/.circleci/config.yml b/.circleci/config.yml
index 9b8a5cb..649d193 100644
--- a/.circleci/config.yml
+++ b/.circleci/config.yml
@@ -4,7 +4,7 @@ orbs:
 executors:
   consul-ecs-test:
     docker:
-      - image: docker.mirror.hashicorp.services/hashicorpdev/consul-ecs-test:0.3.1
+      - image: docker.mirror.hashicorp.services/hashicorpdev/consul-ecs-test:0.3.2
     environment:
       TEST_RESULTS: &TEST_RESULTS /tmp/test-results # path to where test results are saved
```

Then, commit and open a PR with the changes.
