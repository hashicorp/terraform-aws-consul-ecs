# The server app is part of the service mesh. It's called
# by the client app.
resource "aws_ecs_service" "example_server_app" {
  name            = "${var.name}-example-server-app"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = module.example_server_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}


module "example_server_app" {
  source            = "../../modules/mesh-task"
  family            = "${var.name}-example-server-app"
  port              = "9090"
  log_configuration = local.example_server_app_log_config
  container_definitions = [{
    name             = "example-server-app"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_server_app_log_config
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-example-server-app"
      }
    ]
  }]
  retry_join                     = jsondecode(base64decode(hcp_consul_cluster.example.consul_config_file))["retry_join"][0]
  tls                            = true
  consul_server_ca_cert_arn      = aws_secretsmanager_secret.consul_ca_cert.arn
  gossip_key_secret_arn          = aws_secretsmanager_secret.gossip_key.arn
  acls                           = true
  consul_client_token_secret_arn = module.acl_controller.client_token_secret_arn
  acl_secret_name_prefix         = var.name
}

locals {
  example_server_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "app"
    }
  }
}
