module "acl_controller" {
  source     = "../../modules/acl-controller"
  depends_on = [hcp_consul_cluster.example]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller"
    }
  }
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  consul_server_http_addr           = hcp_consul_cluster.example.consul_public_endpoint_url
  ecs_cluster_arn                   = aws_ecs_cluster.this.arn
  region                            = var.region
  subnets                           = module.vpc.private_subnets
  name_prefix                = var.name
}