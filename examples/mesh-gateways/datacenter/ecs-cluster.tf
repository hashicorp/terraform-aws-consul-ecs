resource "aws_ecs_cluster" "this" {
  name               = var.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.name
}

module "acl_controller" {
  source = "../../../modules/acl-controller"

  name_prefix               = var.name
  ecs_cluster_arn           = aws_ecs_cluster.this.arn
  region                    = var.region
  subnets                   = var.private_subnets
  consul_server_http_addr   = "http://${module.dev_consul_server.server_dns}:8500"
  consul_server_ca_cert_arn = var.ca_cert_arn
  launch_type               = "FARGATE"

  consul_bootstrap_token_secret_arn = var.bootstrap_token_arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "acl-controller"
    }
  }

  consul_ecs_image = var.consul_ecs_image
}
