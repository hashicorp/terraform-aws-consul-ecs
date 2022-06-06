resource "aws_ecs_cluster" "this" {
  name               = var.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.name
}

resource "random_string" "name_prefix" {
  length  = 6
  special = false
}

module "acl_controller" {
  source = "../../../modules/acl-controller"

  name_prefix             = random_string.name_prefix.result
  ecs_cluster_arn         = aws_ecs_cluster.this.arn
  region                  = var.region
  subnets                 = var.vpc.private_subnets
  consul_server_http_addr = hcp_consul_cluster.this.consul_private_endpoint_url
  launch_type             = "FARGATE"

  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "acl-controller"
    }
  }

  consul_ecs_image = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:0d327c1"

  consul_partitions_enabled = true
  consul_partition          = "default"
}
