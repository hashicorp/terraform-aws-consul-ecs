// The client app will be deployed in the first datacenter.
// It will reach its upstream located in the second datacenter.
// It has an application load balancer for ingress.
locals {
  example_client_app_name = "${var.name}-${local.primary_datacenter}-example-client-app"
  example_client_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = module.dc1.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "client"
    }
  }
}


module "example_client_app" {
  source                    = "../../modules/mesh-task"
  family                    = local.example_client_app_name
  port                      = "9090"
  consul_ecs_image          = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:0d327c1"
  consul_datacenter         = local.primary_datacenter
  acls                      = true
  consul_http_addr          = "http://${module.dc1.dev_consul_server.server_dns}:8500"
  consul_https_ca_cert_arn  = aws_secretsmanager_secret.ca_cert.arn
  tls                       = true
  consul_server_ca_cert_arn = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  retry_join                = [module.dc1.dev_consul_server.server_dns]
  upstreams = [
    {
      destinationName = "${var.name}-${local.secondary_datacenter}-example-server-app"
      datacenter      = "dc2"
      localBindPort   = 1234
      meshGateway = {
        mode = "local"
      }
    }
  ]
  log_configuration = local.example_client_app_log_config
  container_definitions = [
    {
      name             = "example-client-app"
      image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
      essential        = true
      logConfiguration = local.example_client_app_log_config
      environment = [
        {
          name  = "NAME"
          value = local.example_client_app_name
        },
        {
          name  = "UPSTREAM_URIS"
          value = "http://localhost:1234"
        }
      ]
      portMappings = [
        {
          containerPort = 9090
          hostPort      = 9090
          protocol      = "tcp"
        }
      ]
  }]

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  consul_agent_configuration = <<EOT
  acl = { enable_token_replication = true }
  primary_datacenter = "${local.primary_datacenter}"
EOT
}

resource "aws_ecs_service" "example_client_app" {
  name            = local.example_client_app_name
  cluster         = module.dc1.ecs_cluster.arn
  task_definition = module.example_client_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.dc1.private_subnets
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.example_client_app.arn
    container_name   = "example-client-app"
    container_port   = 9090
  }
  enable_execute_command = true
}

resource "aws_lb" "example_client_app" {
  name               = local.example_client_app_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example_client_app_alb.id]
  subnets            = module.dc1.public_subnets
}

resource "aws_security_group" "example_client_app_alb" {
  name   = "${local.example_client_app_name}-alb"
  vpc_id = module.dc1_vpc.vpc_id

  ingress {
    description = "Access to example client application."
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["${var.lb_ingress_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ingress_from_client_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.example_client_app_alb.id
  security_group_id        = module.dc1_vpc.default_security_group_id
}

resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
  security_group_id        = module.dc1_vpc.default_security_group_id
}

resource "aws_lb_target_group" "example_client_app" {
  name                 = local.example_client_app_name
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = module.dc1_vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "example_client_app" {
  load_balancer_arn = aws_lb.example_client_app.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_client_app.arn
  }
}

