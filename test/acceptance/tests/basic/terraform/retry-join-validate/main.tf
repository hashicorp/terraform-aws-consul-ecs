provider "aws" {
  region = "us-west-2"
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
}