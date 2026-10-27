data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 0
}

resource "aws_ecr_repository" "this" {
  name                 = lower(var.name)
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "null_resource" "this" {
  provisioner "local-exec" {
    environment = {
      K6_VERSION = var.k6_version
    }
    command = <<EOF
docker build --platform linux/amd64 -t k6:local ${path.module}/container && \
docker tag k6:local "${aws_ecr_repository.this.repository_url}:latest" && \
aws ecr get-login-password \
  --region ${data.aws_region.current.name} | \
docker login --username AWS --password-stdin \
  ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com && \
docker push ${aws_ecr_repository.this.repository_url}:latest
EOF
  }

  depends_on = [
    aws_ecr_repository.this
  ]
}

resource "aws_lambda_function" "this" {
  function_name = title(var.name)
  role          = aws_iam_role.assume.arn
  image_uri     = "${aws_ecr_repository.this.repository_url}:latest"
  memory_size   = 256
  timeout       = 900

  #source_code_hash = filebase64sha256("${path.root}/k6-amazon2.zip")
  package_type = "Image"
  publish      = true

  #  layers = [
  #    aws_lambda_layer_version.this.id,
  #  ]

  vpc_config {
    subnet_ids = var.subnets
    security_group_ids = [
      aws_security_group.this.id
    ]
  }

  environment {
    variables = {
      LB_ENDPOINT                 = var.target
      K6_CLOUD_TOKEN              = var.apikey
      K6_INSECURE_SKIP_TLS_VERIFY = true
      XDG_CONFIG_HOME             = "/var/task"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_ecr_repository.this,
    null_resource.this,
  ]
}

resource "aws_security_group" "this" {
  name   = "${title(var.name)}Access"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "egress_all" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 65535
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "assume" {
  name               = "${title(var.name)}Assume"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid = "AWSLambdaBasicExecutionRole"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "execution" {
  name   = "${title(var.name)}Execution"
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.assume.name
  policy_arn = aws_iam_policy.execution.arn
}

resource "aws_iam_policy" "logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "arn:aws:logs:*:*:*",
        Effect : "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.assume.name
  policy_arn = aws_iam_policy.logging.arn
}
