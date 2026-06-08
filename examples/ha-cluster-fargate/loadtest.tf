module "k6lambda" {
  source  = "../../modules/lambda-k6"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets
  target  = module.consul-cluster.mgmt_alb_dns_name
}

resource "aws_lambda_invocation" "k6" {
  count         = var.invoke_loadtest ? 1 : 0
  function_name = module.k6lambda.function_name
  input         = jsonencode({})
}
