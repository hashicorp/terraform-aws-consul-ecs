# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# This is an ALB sitting infront of the API gateway ECS task.
# We configure a HTTP listener and pass the load balancer's
# target group config to the gateway ECS task.
resource "aws_lb" "this" {
  name               = "${var.name}-api-gateway"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.load_balancer.id]
}

resource "aws_lb_target_group" "this" {
  name                 = "${var.name}-api-gateway"
  port                 = 8443
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
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

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "8443"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_security_group" "load_balancer" {
  name        = "${var.name}-api-gateway"
  description = "Security group for ${var.name}-api-gateway"
  vpc_id      = module.vpc.vpc_id
}

# Allow all egress traffic from the LB
resource "aws_security_group_rule" "lb_egress_rule" {
  type              = "egress"
  description       = "Egress rule for ${var.name}-api-gateway"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.load_balancer.id
}

# Allow ingress only from the user's IP. This is done to
# prevent the LB from being exposed to the public internet.
resource "aws_security_group_rule" "lb_ingress_rule" {
  type              = "ingress"
  description       = "Ingress rule for ${var.name}-api-gateway"
  from_port         = 8443
  to_port           = 8443
  protocol          = "-1"
  cidr_blocks       = ["${var.lb_ingress_ip}/32"]
  security_group_id = aws_security_group.load_balancer.id
}