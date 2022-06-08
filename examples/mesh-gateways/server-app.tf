// The server app is deployed in the second datacenter.
// It has no public ingress and can only be reached through the mesh gateways.
locals {
  example_server_app_name = "${var.name}-${local.secondary_datacenter}-example-server-app"
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
  source                       = "../../modules/mesh-task"
  family                       = local.example_server_app_name
  port                         = "9090"
  consul_datacenter            = local.secondary_datacenter
  consul_primary_datacenter    = local.primary_datacenter
  acls                         = true
  enable_acl_token_replication = true
  consul_http_addr             = "http://${module.dc2.dev_consul_server.server_dns}:8500"
  consul_https_ca_cert_arn     = aws_secretsmanager_secret.ca_cert.arn
  tls                          = true
  consul_server_ca_cert_arn    = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn        = aws_secretsmanager_secret.gossip_key.arn
  retry_join                   = [module.dc2.dev_consul_server.server_dns]
  log_configuration            = local.example_server_app_log_config
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

  consul_ecs_image = var.consul_ecs_image
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
