# Locality based routing between ECS tasks

This example demonstrates how Consul routes traffic based on the locality where the ECS tasks are deployed. As of 1.17, Consul only supports locality aware routing within a single partition. Support for multiple partitions and multiple cluster peers will soon be added in the upcoming releases.

**Note**: The locality aware routing feature requires Consul Enterprise.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/locality-aware-routing-arch.png?raw=true)

This terraform example does the following

1. Create an ECS service with a single task that runs the client application's container.
2. Create another ECS service with two tasks spread across available zones within the same AWS region. These tasks host the server application's container.
3. The consul server is also deployed as an ECS task along with an ECS controller.

## Requirements

* `jq`
* `curl`
* Terraform >= 1.2.2
* Authentication credentials for the [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication)

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/locality-aware-routing
```

This module contains everything needed to spin up the example. The only
requirements are:
- You need to pass in the `name` variable. This value will be used as a unique identifier
  for all resources created by the example. The examples below use the name `ecs`.
- You need to pass in the IP address of your workstation via the `lb_ingress_ip`
  variable. This is used for the security groups on the elastic load balancers to ensure
  only you have access to them.
- Consul Enterprise license that needs to be passed to the `consul_license` variable. This license will be used to run the enterprise version of Consul in this example. One way to pass these licenses would be add them to a `.tfvars` file and pass it as an argument to the `terraform apply` command.

Determine your public IP. You can use a site like https://ifconfig.me/:

```console
$ curl ifconfig.me
123.456.789.1%
```

Example `input.tfvars`

```
lb_ingress_ip  = "123.456.789.1"
consul_license = "<license>"
```

Initialize Terraform:

```console
$ terraform init
```

### Terraform Apply

Then apply the Terraform passing in a name and your IP:

```console
$ terraform apply \
    -var name=ecs \
    -var-file=input.tfvars
```

The plan should look similar to:

```shell
Plan: 81 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + client_lb_address             = (known after apply)
  + consul_server_bootstrap_token = (sensitive value)
  + consul_server_url             = (known after apply)
  + ecs_cluster_arn = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 7-10 minutes. When complete, the URLs of the two load
balancers should be in the output, along with the bootstrap token for the Consul server:

```shell
Apply complete! Resources: 81 added, 0 changed, 0 destroyed.

Outputs:

client_lb_address = "http://example-client-app-1959503271.us-west-2.elb.amazonaws.com:9090/ui"
consul_server_bootstrap_token = <sensitive>
consul_server_url = "http://ecs-dc1-consul-server-713584774.us-west-2.elb.amazonaws.com:8500"
ecs_cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/my-ecs-cluster"
```

### Explore

Get the bootstrap token for the Consul server from the Terraform output:

```console
$ terraform output -json | jq -r .consul_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7
```

If you click on the URL of the `consul_server_url`, you should be able
to view the Consul UI and log in using the `consul_server_bootstrap_token` above:

![Consul dc1 UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/locality-aware-dc1-ui.png?raw=true)

If you browse to the URL of the `client_lb_address`, the example application UI should be displayed:

![Example App UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/locality-aware-app-ui.png?raw=true)

Notice the IP of the upstream server application's task. Because of the locality parameters added during the service registration, Consul takes care of routing traffic from the client application to the server application task within the same availability zone. You can read more about the locality aware routing feature [here](https://developer.hashicorp.com/consul/docs/v1.17.x/connect/manage-traffic/route-to-local-upstreams?ajs_aid=54615e8b-87b1-40fa-aecc-3e16280d6a88&product_intent=consul)

#### Testing failover

Terminate the server app's task that resides in the same availability zone as that of the client app's task. This can be done by manually stopping the desired task from the ECS UI or with the following CLI command

```
aws ecs stop-task --region ${AWS_REGION} --cluster ${CLUSTER_ARN} --task ${TASK_ARN} --reason "Testing failover"
```

Once the task gets successfully stopped, try making calls to the server application from `client_lb_address`. The first few calls should fail but once the failure breaches a particular threshold calls will automatically be failed over to the server app's task present in another availability zone within the same AWS region.

![Example App UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/locality-aware-dc1-failover-ui.png?raw=true)

## Cleanup

Once you've finished testing, be sure to clean up the resources you've created:

```console
$ terraform destroy \
    -var name=ecs \
    -var-file=input.tfvars
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're
ready to deploy your own applications into the service mesh.
