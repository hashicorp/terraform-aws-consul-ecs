# Consul HA Cluster backed by EFS storage on Fargate Example

This example deploys a new VPC, EFS Cluster and ECS Cluster to host 3 Consul Servers in HA with 3 Consul Agents. A K6
container is built by local provisioner and stored in ECR for use in Lambda to load test the KV system on EFS with Raft.

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/ha-cluster-fargate
```

> This module utilizes the Consul Image with a Go-Discover module version
> v0.0.0-20220714221025-1c234a67149a


The following `variables.auto.tfvars` file can be used to target a specific image.
```terraform
consul_image = "registry.gitlab.com/fdir/consul:latest"
```

Create the Consul CA Key and Cert, Client and CLI keypairs and an ALB keypair.
```bash
make certs
```

Initialize Terraform:

```bash
terraform init
```

### Terraform Apply

Then apply the Terraform:

```bash
terraform apply
```

In this deployment the ALB is internal to reduce the cost of load test traffic.

Tail the logs in cloudwatch until the Cluster has quorum and all agents have joined.

### Interact with a server

Get a cluster By Name

```bash
aws ecs list-clusters | jq -r '.clusterArns[0]'
```

Get the consul0 service task
```bash
aws ecs list-tasks --cluster consul-dc1 --service-name Consul0
```

List the consul members
```bash
aws ecs execute-command --interactive --cluster consul-dc1 --task $TASK_ID --container consul-server --command "consul members"
```
```console
The Session Manager plugin was installed successfully. Use the AWS CLI to start a session.
Starting session with SessionId: ecs-execute-command-00cd14d5b53dd200c
Node           Address          Status  Type    Build      Protocol  DC   Partition  Segment
consul0        10.0.2.30:8301   alive   server  1.15.0dev  2         dc1  default    <all>
consul1        10.0.4.75:8301   alive   server  1.15.0dev  2         dc1  default    <all>
consul2        10.0.6.118:8301  alive   server  1.15.0dev  2         dc1  default    <all>
consul-agent0  10.0.2.145:8301  alive   client  1.15.0dev  2         dc1  default    <default>
consul-agent1  10.0.4.37:8301   alive   client  1.15.0dev  2         dc1  default    <default>
consul-agent2  10.0.6.160:8301  alive   client  1.15.0dev  2         dc1  default    <default>
```

Start a session on the service, using cluster name and task id
```bash
aws ecs execute-command --interactive --cluster consul-dc1 --task 0b5744fd84444932ba832f2da298f6a2 --container consul-server --command sh
```

### Start a Load Test

When ready to run load test, invoke the lambda.
```bash
terraform apply -auto-approve -var 'invoke_loadtest=true'
```

You can follow the load test while in progress in the cloudwatch log group `/aws/lambda/K6Lambda`.

If you want to rerun the load test, taint the invocation and apply again.
```bash
terraform taint aws_lambda_invocation.k6[0]
terraform apply -auto-approve -var 'invoke_loadtest=true'
```

## Cleanup

Once you've done testing, be sure to clean up the resources you've created:

```bash
terraform destroy -auto-approve
```
