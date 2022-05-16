// The server app is deployed in the second datacenter.
locals {
  example_server_app_name = "${var.name}-${var.datacenter_names[1]}-example-server-app"
  example_server_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = module.dc2.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "server"
    }
  }
}

module "example_server_app" {
  source            = "../../modules/mesh-task"
  family            = local.example_server_app_name
  port              = "9090"
  log_configuration = local.example_server_app_log_config
  consul_datacenter = var.datacenter_names[1]
  consul_ecs_image  = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
  container_definitions = [{
    name             = "example-server-app"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_server_app_log_config
    environment = [
      {
        name  = "NAME"
        value = local.example_server_app_name
      }
    ]
  }]
  retry_join = [module.dc2.dev_consul_server.server_dns]
}

resource "aws_ecs_service" "example_server_app" {
  name            = local.example_server_app_name
  cluster         = module.dc2.ecs_cluster.arn
  task_definition = module.example_server_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.dc2.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}
