# Run the Consul dev server as an ECS task.
module "dev_consul_server" {
  name                        = "${var.name}-consul-server"
  source                      = "../../modules/dev-server"
  ecs_cluster_arn             = aws_ecs_cluster.this.arn
  subnet_ids                  = module.vpc.private_subnets
  vpc_id                      = module.vpc.vpc_id
  lb_enabled                  = true
  lb_subnets                  = module.vpc.public_subnets
  lb_ingress_rule_cidr_blocks = ["${var.lb_ingress_ip}/32"]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-server"
    }
  }
  launch_type = "FARGATE"

  tls                       = true
  gossip_encryption_enabled = true
  acls                      = true
}

resource "aws_security_group_rule" "consul_server_ingress" {
  description              = "Access to Consul dev server from default security group"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.vpc.default_security_group_id
  security_group_id        = module.dev_consul_server.security_group_id
}


module "ecs_controller" {
  source = "../../modules/controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-ecs-controller"
    }
  }
  consul_bootstrap_token_secret_arn = module.dev_consul_server.bootstrap_token_secret_arn
  consul_server_http_addr           = "https://${module.dev_consul_server.server_dns}:8501"
  consul_server_ca_cert_arn         = module.dev_consul_server.ca_cert_arn
  ecs_cluster_arn                   = aws_ecs_cluster.this.arn
  region                            = var.region
  subnets                           = module.vpc.private_subnets
  name_prefix                       = var.name
}
