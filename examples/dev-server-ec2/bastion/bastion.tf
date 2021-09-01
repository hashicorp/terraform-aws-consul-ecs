// Bastion server to SSH into container instances in a private subnet
data "aws_ami" "bastion" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  owners = ["amazon"]
}

resource "aws_key_pair" "pubkey" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.public_ssh_key))
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.bastion.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.pubkey.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "${var.name}-consul-ecs-ec2-bastion"
  }
}

resource "aws_security_group" "bastion" {
  name   = "${var.name}-consul-ecs-ec2-bastion-group"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ssh_rule" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${var.ingress_ip}/32"]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "egress_rule" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.bastion.id
}

// Modify the security group associated with the *container instances* to allow ingress from the bastion
resource "aws_security_group_rule" "ssh_ingress_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = var.destination_security_group
}
