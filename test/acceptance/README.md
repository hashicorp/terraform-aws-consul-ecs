## Acceptance Tests

These tests run the Terraform code.

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

   ```sh
   cd ..
   ```

   Then export the necessary data from the Terraform state into environment variables:
   
   ```sh
   export ecs_cluster_arn=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .ecs_cluster_arn.value | tee /dev/tty)
   export private_subnets=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .private_subnets.value | tee /dev/tty)
   export suffix=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .suffix.value | tee /dev/tty)
   export region=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .region.value | tee /dev/tty)
   export log_group_name=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .log_group_name.value | tee /dev/tty)
   export tags=$(terraform output -state ./setup-terraform/terraform.tfstate -json | jq -rc .tags.value | tee /dev/tty)
   ```

   **NOTE:** If you see an empty line in the output from this command then
   something wasn't exported properly.

   Now you're ready to run the acceptance tests.
1. To run the tests, use `go test` from the `test/acceptance` directory:

   ```sh
   go test ./... -p 1 -timeout 30m -v -failfast \
     -ecs-cluster-arn="$ecs_cluster_arn" \
     -subnets="$private_subnets" \
     -suffix="$suffix" \
     -region="$region" \
     -log-group-name="$log_group_name" \
     -tf-tags="$tags"
   ```
