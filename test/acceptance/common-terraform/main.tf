provider "aws" {
  region = var.region
}

module "acl_controller" {
  count  = var.secure ? 1 : 0
  source = "../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.consul_bootstrap_token_secret_arn
  consul_server_http_addr           = var.consul_server_http_addr
  consul_server_ca_cert_arn         = var.consul_server_ca_cert_arn
  ecs_cluster_arn                   = var.ecs_cluster_arn
  region                            = var.region
  subnets                           = var.private_subnets
  name_prefix                       = var.suffix
  consul_ecs_image                  = var.consul_ecs_image
}

resource "aws_ecs_service" "test_client" {
  name            = "test_client_${var.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.test_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_client" {
  source = "../../../modules/mesh-task"
  family = "test_client_${var.suffix}"
  container_definitions = [
    {
      name             = "basic"
      image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
      essential        = true
      logConfiguration = local.test_client_log_configuration
      environment = [
        {
          name  = "UPSTREAM_URIS"
          value = "http://localhost:1234"
        }
      ]
      linuxParameters = {
        initProcessEnabled = true
      }
      # Keep the client running for 10 seconds to validate graceful shutdown behavior.
      entryPoint = ["/bin/sh", "-c", <<EOT
/app/fake-service &
export PID=$!
trap "{ echo 'TEST LOG: on exit'; kill $PID; }" 0
function onterm() {
    echo "TEST LOG: Caught sigterm. Sleeping 10s..."
    sleep 10
    exit 0
}
trap onterm TERM
wait $PID
EOT
      ]
      healthCheck = {
        command  = ["CMD-SHELL", "echo 1"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    },
    {
      # Inject an additional container to monitor apps during task shutdown.
      name             = "shutdown-monitor"
      image            = "docker.mirror.hashicorp.services/golang:1.17-alpine"
      essential        = false
      logConfiguration = local.test_client_log_configuration
      # AWS: "We do not enforce a size limit on the environment variables..."
      # Then, the max environment var length is ~32k
      environment = [{
        name  = "GOLANG_MAIN_B64"
        value = base64encode(file("${path.module}/shutdown-monitor.go"))
      }]
      # NOTE: `go run <file>` signal handling is different: https://github.com/golang/go/issues/40467
      entryPoint = ["/bin/sh", "-c", <<EOT
echo "$GOLANG_MAIN_B64" | base64 -d > main.go
go build main.go
exec ./main
EOT
      ]
    }
  ]
  retry_join = var.retry_join
  upstreams = [
    {
      destination_name = var.server_service_name
      local_bind_port  = 1234
    }
  ]
  log_configuration = local.test_client_log_configuration
  outbound_only     = true

  tls                            = var.secure
  consul_server_ca_cert_arn      = var.secure ? var.consul_server_ca_cert_arn : ""
  gossip_key_secret_arn          = var.secure ? var.consul_gossip_key_secret_arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image
}

resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.test_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_server" {
  source              = "../../../modules/mesh-task"
  family              = "test_server_${var.suffix}"
  consul_service_name = var.server_service_name
  container_definitions = [{
    name             = "basic"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.test_server_log_configuration
  }]
  retry_join        = var.retry_join
  log_configuration = local.test_server_log_configuration
  checks = [
    {
      checkid  = "server-http"
      name     = "HTTP health check on port 9090"
      http     = "http://localhost:9090/health"
      method   = "GET"
      timeout  = "10s"
      interval = "2s"
    }
  ]
  port = 9090

  tls                            = var.secure
  consul_server_ca_cert_arn      = var.secure ? var.consul_server_ca_cert_arn : ""
  gossip_key_secret_arn          = var.secure ? var.consul_gossip_key_secret_arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image
}

locals {
  test_server_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_server_${var.suffix}"
    }
  }

  test_client_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_client_${var.suffix}"
    }
  }
}
