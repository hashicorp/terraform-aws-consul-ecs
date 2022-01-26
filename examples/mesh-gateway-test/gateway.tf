locals {
  dc1_gateway_name = "${var.name}-${var.datacenter_names[0]}-mesh-gateway"
  dc1_gateway_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = module.dc1.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "mesh-gateway"
    }
  }
  dc2_gateway_name = "${var.name}-${var.datacenter_names[1]}-mesh-gateway"
  dc2_gateway_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = module.dc2.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "mesh-gateway"
    }
  }
}

module "dc1-gateway" {
  source = "../../modules/gateway-task"

  family = local.dc1_gateway_name
  // '-mesh-gateway' is appended to this
  consul_service_name = "${var.name}-${var.datacenter_names[0]}"
  retry_join          = [module.dc1.dev_consul_server.server_dns]
  kind                = "mesh-gateway"
  consul_datacenter   = var.datacenter_names[0]

  log_configuration = local.dc1_gateway_log_config
}

resource "aws_ecs_service" "dc1_gateway" {
  // Mesh-init '-mesh-gateway' but we need it here to distinguish the service.
  name            = local.dc1_gateway_name
  cluster         = module.dc1.ecs_cluster.arn
  task_definition = module.dc1-gateway.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.dc1.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

// DC2 gateway
module "dc2-gateway" {
  source = "../../modules/gateway-task"

  family              = local.dc2_gateway_name
  consul_service_name = "${var.name}-${var.datacenter_names[1]}"
  retry_join          = [module.dc2.dev_consul_server.server_dns]
  kind                = "mesh-gateway"
  consul_datacenter   = var.datacenter_names[1]

  log_configuration = local.dc2_gateway_log_config
}

resource "aws_ecs_service" "dc2_gateway" {
  name            = local.dc2_gateway_name
  cluster         = module.dc2.ecs_cluster.arn
  task_definition = module.dc2-gateway.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.dc2.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}
