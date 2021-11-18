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

  tags = var.tags
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
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
}

resource "aws_ecs_service" "load_client" {
  name            = "${var.name}-load-client"
  cluster         = var.cluster_arn
  task_definition = module.load_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.private_subnets
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "load_client" {
  source = "../../../../../modules/mesh-task"
  family = "${var.name}-load-client"
  container_definitions = [{
    name      = "load"
    image     = "buoyantio/slow_cooker"
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
}

# TODO These are annoying because it frequently blocks refreshes and deletes. Is there a better way to do this?
resource "consul_config_entry" "service_intentions" {
  kind = "service-intentions"
  name = "${var.name}-test-server"

  config_json = jsonencode({
    Sources = [
      {
        Action = "allow"
        Name   = "${var.name}-load-client"
      }
    ]
  })

  depends_on = [module.test_server.task_definition_arn, module.load_client.task_definition_arn]
}
