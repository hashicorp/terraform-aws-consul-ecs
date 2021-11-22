resource "aws_ecs_service" "test_server" {
  name            = "${var.name}-test-server"
  cluster         = var.cluster_arn
  task_definition = module.test_server.task_definition_arn
  desired_count   = var.server_instances_per_service_group
  network_configuration {
    subnets = var.private_subnets
  }
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags        = var.tags
  launch_type = "FARGATE"
}

module "test_server" {
  source = "../../../../../modules/mesh-task"
  family = "${var.name}-test-server"
  container_definitions = [{
    name      = "basic"
    image     = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential = true
    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost:9090 || exit 1"]
      interval = 10
    }
    },
  ]
  datadog_api_key = var.datadog_api_key
  retry_join      = ["provider=aws region=${var.region} tag_key=consul-ecs-perf tag_value=consul-ecs-perf"]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "${var.name}-test-server"
    }
  }
  port                          = 9090
  additional_task_role_policies = var.additional_task_role_policies

  tls                            = true
  consul_server_ca_cert_arn      = var.ca_cert_arn
  gossip_key_secret_arn          = var.gossip_key_secret_arn
  acls                           = true
  acl_secret_name_prefix         = var.suffix
  consul_client_token_secret_arn = var.consul_client_token_secret_arn
  consul_ecs_image               = var.consul_ecs_image
  envoy_image                    = "ghcr.io/erichaberkorn/envoy:latest"
}

resource "aws_ecs_service" "load_client" {
  name            = "${var.name}-load-client"
  cluster         = var.cluster_arn
  task_definition = module.load_client.task_definition_arn
  desired_count   = var.client_instances_per_service_group
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "load_client" {
  source = "../../../../../modules/mesh-task"
  family = "${var.name}-load-client"
  container_definitions = [{
    name      = "load"
    image     = "ghcr.io/erichaberkorn/slow_cooker:latest" # a clone to avoid rate limits
    essential = true
    command = [
      "-qps", "1000",
      "-concurrency", "16",
      "-metric-addr", "0.0.0.0:9102",
      "http://127.0.0.1:1235",
    ]
    linuxParameters = {
      initProcessEnabled = true
    }
  }]
  datadog_api_key               = var.datadog_api_key
  additional_task_role_policies = var.additional_task_role_policies
  retry_join                    = ["provider=aws region=${var.region} tag_key=consul-ecs-perf tag_value=consul-ecs-perf"]
  upstreams = [
    {
      destination_name = "${var.name}-test-server"
      local_bind_port  = 1235
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "${var.name}-load-client"
    }
  }
  outbound_only = true

  tls                            = true
  consul_server_ca_cert_arn      = var.ca_cert_arn
  gossip_key_secret_arn          = var.gossip_key_secret_arn
  acls                           = true
  acl_secret_name_prefix         = var.suffix
  consul_client_token_secret_arn = var.consul_client_token_secret_arn
  consul_ecs_image               = var.consul_ecs_image
  envoy_image                    = "ghcr.io/erichaberkorn/envoy:latest"
}
