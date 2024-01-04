#resource "aws_key_pair" "deployer" {
#  key_name   = "deployer-key"
#  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCthfQW8EwnjNjDI74x1ogFLI4NIE0JdczGP+v/FbDFvofbVtZ4S9dz2g9XTjimosnj65IUU7HV1F9hMhhT+1KbRvfUE2Btkrk6TJUm5bph5kmRlTcuCDIBBU5R4stDw2fC1Qdy+A8UYVlDABy7RtasVdhYKei/glyaF4hbsj4Ve/gHValUJj9Ul1xh8JiBkODtrAZsY7y++VAlya4xFURi5g0yBnRydvizoGWyrP47HJReHQPKBc3OUFmka2TX5hYj3YXufrbB8MujApsF81RyNh/sDycr0e4JpkD8YAa4YY3xG5ohoG7YUOBRwilvVxGahX6zy/ZbFCXIFjRJX9VZk0eTdfGVYcNHiWGDASuG33n/UuSeLv++vKMDs1yS1sxcCXYQEt2x1eFmgKJlADLT7UmS31PeFcZQ20MMyw8FNO3ZFGzdEZag4E0oHMQFAeQ3+3/vsNM9WbOlaU7y829w53/+FbgMrK8tcFG08TsgASkm8XAi//2SlEm5Sd67chhQbeODAKPPOIYEyHsdiAorPAO3UKboCcNU2pzsUNgjZECx5E5XQ+Rgfh8Rm0zfUr+IHv3kRrCeSR6j3+bPOfkStfvRtNFk11y0bpSabiDm1uqpVmJ8ahQxweva6Kl5TV3DQk85F20Ilrn3qP6qfw2to3x1VCIVCqCzg3w5RK8gPQ== kavish.kumar@hashicorp.com"
#}

resource "aws_security_group" "ec2" {
  name        = "allow_efs"
  description = "Allow efs outbound traffic"
  vpc_id      = module.vpc.vpc_id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_efs"
  }
}

#resource "aws_security_group_rule" "ingress_from_ec2_to_efs" {
#  type                     = "ingress"
#  from_port                = 0
#  to_port                  = 0
#  protocol                 = "-1"
#  source_security_group_id = aws_security_group.ec2.id
#  security_group_id        = aws_security_group.efs.id
#}

resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "Allows inbound efs traffic from ec2"
  vpc_id      = module.vpc.vpc_id

  ingress {
#    security_groups = [aws_security_group.ec2.id, aws_security_group.example_server_app_alb.id]
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
#    security_groups = [aws_security_group.ec2.id, aws_security_group.example_server_app_alb.id]
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#resource "aws_security_group_rule" "ingress_from_efs_to_default" {
#  type                     = "ingress"
#  from_port                = 0
#  to_port                  = 0
#  protocol                 = "-1"
#  source_security_group_id = aws_security_group.efs.id
#  security_group_id        = data.aws_security_group.vpc_default.id
#}

#resource "aws_security_group_rule" "ingress_from_default_to_efs" {
#  type                     = "ingress"
#  from_port                = 0
#  to_port                  = 0
#  protocol                 = "-1"
#  source_security_group_id = aws_security_group.efs.id
#  security_group_id        = data.aws_security_group.vpc_default.id
#}

#resource "aws_security_group_rule" "ingress_from_external_server_alb_to_efs" {
#  type                     = "ingress"
#  from_port                = 0
#  to_port                  = 0
#  protocol                 = "-1"
#  source_security_group_id = aws_security_group.efs.id
#  security_group_id        = aws_security_group.example_server_app_alb.id
#}

# this was provisioned to test whether certs copied by the
# efs_mount_instance are accessible post mount
#resource "aws_instance" "efs_mount_instance_test" {
#  ami                         = "ami-05fa00d4c63e32376"
#  instance_type               = "t2.micro"
#  subnet_id                   = module.vpc.public_subnets[0]
#  associate_public_ip_address = true
#  vpc_security_group_ids      = [aws_security_group.ec2.id]
#  key_name                    = "kavishECS"
#  tags = {
#    Name = "efs_mount_instance_test"
#  }
#}

resource "aws_instance" "efs_mount_instance" {
  ami                         = "ami-05fa00d4c63e32376"
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  key_name                    = "kavishECS"
  tags = {
    Name = "efs_mount_instance"
  }
}

resource "aws_efs_file_system" "certs_efs" {
  creation_token   = "certs-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
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



# Creating Mount Point for EFS
resource "null_resource" "configure_nfs" {
  depends_on = [aws_efs_mount_target.efs_mt]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.private_key)
    host        = aws_instance.efs_mount_instance.public_ip
    timeout     = "20s"
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd -y -q",
      "sleep 15",
      "sudo yum install httpd php git -y -q ",
      "sleep 10",
      "sudo yum install php  -y -q ",
      "sleep 5",
      "sudo systemctl start httpd",
      "sleep 5",
      "sudo systemctl enable httpd",
      "sleep 5",
      "sudo yum install nfs-utils -y -q ", # Amazon ami has pre installed nfs utils
      "sleep 15",
      "sudo service rpcbind restart",
      "sleep 15",
      # Mounting Efs
      "sudo mkdir ${var.certs_mount_path}",
      "sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.certs_efs.dns_name}:/  ${var.certs_mount_path}",
      "sleep 15",
      "sudo chmod go+rwx ${var.certs_mount_path}",
      "sudo git clone https://github.com/kkavish/test-certs.git ${var.certs_mount_path}",
      "sudo chmod go-w ${var.certs_mount_path}",
    ]
  }
}