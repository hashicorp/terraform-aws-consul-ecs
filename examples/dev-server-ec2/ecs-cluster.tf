resource "aws_iam_role" "instance_role" {
  name = "${var.name}-consul-ecs-instance-role"

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
  name = "${var.name}-consul-ecs-instance-profile"
  role = aws_iam_role.instance_role.name
}

resource "aws_launch_configuration" "launch_config" {
  // Use name_prefix + create_before_destroy to avoid a "cannot delete" error.
  // https://github.com/hashicorp/terraform-provider-aws/issues/8485
  name_prefix = "${var.name}-consul-ecs"

  // DEPRECATED: This is an ECS-Optimized Amazon Linux 2 ami, which is no longer supported.
  // We should use a standard image and install the ecs agent on it.
  // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_container_instance.html
  image_id             = "ami-09d2c35d7664ddd48"
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  security_groups      = [data.aws_security_group.vpc_default.id]

  // Agent config.
  // https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-agent-config.html
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${var.name} >> /etc/ecs/ecs.config
EOF

  key_name = var.public_ssh_key != null ? module.bastion[0].keypair_name : null

  // In awsvpc mode, ENIs are the limited resource.
  // The smallest, cheapest instance types have a max of 2 ENIs.
  // One is used for the primary ENI, leaving only one ENI to run one Task :(
  //
  // Pricing is such that three t3a.nano instances seems to be cheapest for 3 ENIs.
  // In the ECS cluster, a t3a.nano exposes only 460 MiB of memory to schedule Tasks,
  // so we've reduced the memory requirement of our tasks to fit (compared to Fargate).
  instance_type = "t3a.nano"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "scaling_group" {
  name                = "${var.name}-consul-ecs-autoscaling-group"
  vpc_zone_identifier = module.vpc.private_subnets

  launch_configuration = aws_launch_configuration.launch_config.name

  desired_capacity = 3
  min_size         = 3
  max_size         = 3

  // https://docs.aws.amazon.com/autoscaling/ec2/userguide/healthcheck.html
  health_check_grace_period = 60
  health_check_type         = "EC2"
  wait_for_capacity_timeout = "2m"
}

resource "aws_ecs_cluster" "this" {
  name = var.name
}

// Optional bastion server, to login to container instances
module "bastion" {
  source = "./bastion"
  count  = var.public_ssh_key != null ? 1 : 0

  name                       = var.name
  ingress_ip                 = var.lb_ingress_ip
  public_ssh_key             = var.public_ssh_key
  vpc_id                     = module.vpc.vpc_id
  subnet_id                  = module.vpc.public_subnets[0]
  destination_security_group = data.aws_security_group.vpc_default.id
}
