## Acceptance Tests

These tests run the Terraform code. For scenario based tests please refer to [this](./examples/README.md) document.

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

   Switch back to the `test/acceptance/tests` directory:

1. To run the tests, use `go test` from the `test/acceptance/tests` directory:

   For tests that use Consul Enterprise outside of HCP, you must set the
   `CONSUL_LICENSE` environment variable to a Consul Enterprise license key.

   ```sh
   export CONSUL_LICENSE=$(cat path/to/license-file)
   go test ./... -p 1 -timeout 30m -v -failfast
   ```

   You may want to add the `-no-cleanup-on-failure` flag if you're debugging
   a failing test. Without this flag, the tests will delete all resources
   regardless of passing or failing.

   You can filter tests by adding the `-run <regex>` option. For example, this
   would only run non enterprise cases of TestBasic:

   ```sh
   go test ./... -p 1 -timeout 30m -v -failfast -run 'TestBasic/.*,enterprise:_false'
   ```

### Cleanup

If the tests haven't cleaned up after themselves, it's easiest to
re-run the test cases that failed to clean up. The test will run again
and hopefully complete successfully and destroy their resources.

If re-running the test case is not possible, then you can run `terraform destroy`
in the test directory containing the terraform state file (`*.tfstate`), although
this takes some extra effort.

TestBasic uses multiple state files to isolate resources for parallel test
runs. You must pass the `-state` argument with the correct state file. To
cleanup resources for all cases of TestBasic, you must run `terraform destroy
-state terraform-<index>.tfstate` for each state file.

```sh
cd test/acceptance/tests/basic/terraform/basic-install`.
terraform destroy -var-file <SEE-BELOW> -state terraform-0.tfstate
terraform destroy -var-file <SEE-BELOW> -state terraform-1.tfstate
terraform destroy -var-file <SEE-BELOW> -state terraform-2.tfstate
```

Additionally, you must pass in the correct variables when running `terraform destroy`:

* Grab outputs from setup-terraform

    ```
    cd test/acceptance/setup-terraform
    terraform output > ../tests/basic/terraform/basic-install/setup-outputs.hcl
    cd ../tests/basic/terraform/basic-install/
    ```

* Edit `setup-outputs.hcl` as-needed for this particular module, until `terraform destory` works.
  All the resources are in the state file, so in most cases the values of the variables won't matter
  since Terraform still knows what to destroy. For example, the following changes might work for TestBasic,
  but this will be different for the HCP tests.

    ```
    terraform destroy -var-file setup-outputs.hcl -state terraform-2.tfstate
    # didn't work? Edit setup-outputs.hcl to modify variables and then retry. See below for tips for TestBasic.
    ```

  * Use matching indexes for the state file, ECS cluster, and Consul datacenter.
    If you are using `terraform-2.tfstate`, then use the `consul-ecs-<suffix>-2` cluster and the `dc2` datacenter.
  * Remove `ecs_cluster_arns` (list) and set `ecs_cluster_arn` (string).
  * Set `consul_datacenter`
  * Remove `tolist()` and `tomap()` wrappers.
  * Replace `token = <sensitive>` (or remove it if not needed, such as in this example)
  * Set `suffix = "nosuffix"`. We just need a lowercase value.
