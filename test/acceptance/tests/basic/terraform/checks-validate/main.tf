provider "aws" {
  region = "us-west-2"
}

variable "checks_file" {
  type = string
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  retry_join    = ["test"]
  outbound_only = true
  checks        = jsondecode(file("${path.module}/${var.checks_file}"))
}
