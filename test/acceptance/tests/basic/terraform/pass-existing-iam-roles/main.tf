// We test this with a Terraform plan only.

provider "aws" {
  region = "us-west-2"
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  retry_join    = ["test"]
  outbound_only = true

  // Validate we can pass existing roles.
  // Users will use a data source to retrieve the role, and pass it in.
  task_role      = data.aws_iam_role.task
  execution_role = data.aws_iam_role.execution
}

data "aws_iam_role" "task" {
  name = aws_iam_role.task.name
}

data "aws_iam_role" "execution" {
  name = aws_iam_role.execution.name
}

// Testing passing task/execution role into mesh-task
resource "aws_iam_role" "task" {
  name = "test-consul-ecs-iam-role-passing_task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_role" "execution" {
  name = "test-consul-ecs-iam-role-passing_execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
