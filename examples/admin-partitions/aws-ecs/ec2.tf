// Setup EC2 container instances for EC2 launch type tests
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

locals {
  ec2_enabled       = var.launch_type == "EC2"
  ecs_optimized_ami = nonsensitive(data.aws_ssm_parameter.ecs_optimized_ami.value)
}

resource "aws_iam_role" "instance_role" {
  count = local.ec2_enabled ? 1 : 0

  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  ]
}

resource "aws_iam_instance_profile" "instance_profile" {
  count = local.ec2_enabled ? 1 : 0

  name = local.name
  role = aws_iam_role.instance_role[count.index].name
}

resource "aws_instance" "instances" {
  count = local.ec2_enabled ? var.instance_count : 0

  ami                  = local.ecs_optimized_ami
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.instance_profile[0].name
  // Spread instances across subnets
  subnet_id              = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.cluster_1.name} >> /etc/ecs/ecs.config
EOF

  tags = merge(var.tags, {
    Name = local.name
  })
}
