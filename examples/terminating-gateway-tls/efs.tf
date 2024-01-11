# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "Allows inbound efs traffic from ec2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    security_groups = [
      data.aws_security_group.vpc_default.id,
      aws_security_group.example_server_app_alb.id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "certs_efs" {
  creation_token = "certs-efs"
  tags = {
    Name = "Certs"
  }
}


resource "aws_efs_mount_target" "efs_mt" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.certs_efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# both external app server and gateway server are deployed in the default vpc
resource "aws_security_group_rule" "ingress_from_default_vpc_to_efs" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.vpc_default.id
  security_group_id        = aws_security_group.efs.id
}