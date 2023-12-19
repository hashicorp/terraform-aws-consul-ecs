## Scenario based tests

These tests deploy the terraform code present under the `examples/` folder and performs custom validations on the same.

These tests are run as part of [CI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/.github/workflows/nightly-ecs-examples-validator.yml). The workflow is setup in a way that deployments happen in multiple stages one after the other. We made a conscious choice to run atmost 4 parallel deployments/test jobs in the CI to make sure that we don't exceed the VPC limits set up in the target AWS account.

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

1. Make sure to set relevant environment variables to configure AWS and HCP (if you are running HCP based scenarios) credentials.

1. Make sure to set the `TEST_SCENARIO` environment variable. This must match one of the scenarios listed in the `scenarioFuncs` map present in [main.go](./main_test.go).

1. To run the tests, use `go test` from the `test/acceptance/examples` directory:

   For tests that use Consul Enterprise outside of HCP, you must set the
   `CONSUL_LICENSE` environment variable to a Consul Enterprise license key.

   ```sh
   export CONSUL_LICENSE=$(cat path/to/license-file)
   TEST_SCENARIO=EC2 go test -run TestScenario -p 1 -timeout 30m -v
   ```

   You may want to set the `NO_CLEANUP_ON_FAILURE` environment variable if you're debugging
   a failing test. Without this variable, the tests will delete all resources
   regardless of passing or failing.

### Adding a new scenario

1. We expect every scenario to implement the `Scenario` interface present [here](./scenarios/scenario.go). Similar to existing examples, add a new folder corresponding to your scenario under the `scenarios/` subfolder and add relevant code into the same.

1. Make sure to add the scenario as part of the `scenarioFuncs` map in [this](./main.go) file.

1. If you want your scenario to run as part of CI, make sure to add it to the matrix list in [this](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/.github/workflows/nightly-ecs-examples-validator.yml) workflow file. If the number of parallel jobs within a matrix exceeds 4, make sure to create a new matrix job that is dependent on the existing ones and add your scenario there.