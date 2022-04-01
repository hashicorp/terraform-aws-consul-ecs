## Acceptance Tests

These tests run the Terraform code.

### Prerequisites

The following prerequisites are needed to run the acceptance tests: 

- [Go](https://go.dev/dl/) (`go test`)
- [Terraform](https://www.terraform.io/downloads) (`terraform`)
   - [Authentication for AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication)
   - [Authentication for HCP provider](https://registry.terraform.io/providers/hashicorp/hcp/latest/docs/guides/auth)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (`aws`)
   - [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [Amazon ECS CLI](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_CLI_installation.html) (`ecs-cli`)

### Instructions

1. To run the tests, first you must run the setup terraform in `setup-terraform`.
   This Terraform creates a VPC and ECS cluster.

   ```sh
   cd setup-terraform
   terraform init
   terraform apply
   ```
1. Now you can run the tests. The tests accept flags for passing in information about the
   VPC and ECS cluster you've just created.

   Switch back to the `test/acceptance` directory:

1. To run the tests, use `go test` from the `test/acceptance` directory:

   ```sh
   go test ./... -p 1 -timeout 30m -v -failfast
   ```

   You may want to add the `-no-cleanup-on-failure` flag if you're debugging
   a failing test. Without this flag, the tests will delete all resources
   regardless of passing or failing.

### Cleanup

If the tests haven't cleaned up after themselves you must run `terraform destroy`
in each directory, e.g. `test/acceptance/tests/basic/terraform/basic-install`.
