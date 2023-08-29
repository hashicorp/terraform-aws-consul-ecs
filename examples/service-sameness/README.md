# Peering of Consul clusters via Mesh gateways on ECS.

This example demonstrates Consul's service sameness usecase using mesh gateways on ECS. This feature only works with a Consul enterprise installation.

![Example architecture](../../_docs/sameness-arch.png?raw=true)

## Requirements

* `jq`
* `curl`
* `terraform`
* `aws` CLI
* AWS credentials

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/service-sameness
```

This module contains everything needed to spin up the example. The only
requirements are:
- You need to pass in the `name` variable. This value will be used as a unique identifier
  for all resources created by the example. The examples below use the name `con`.
- You need to pass in the IP address of your workstation via the `lb_ingress_ip`
  variable. This is used for the security groups on the elastic load balancers to ensure
  only you have access to them.
- Couple of Consul Enterprise licenses that needs to be passed to the `dc1_consul_license` and `dc2_consul_license` variables. One way to pass these licenses would be add them to a `.tfvars` file and pass it as an argument to the `terraform apply` command. Example `input.tfvars`

```
dc1_consul_license = "<license_1>"
dc2_consul_license = "<license_2>"
```

Determine your public IP. You can use a site like https://ifconfig.me/:

```console
$ curl ifconfig.me
123.456.789.1%
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
    -var lb_ingress_ip=123.456.789.1 \
    -var-file=input.tfvars
```

The plan should look similar to:

```shell
Plan: 248 to add, 0 to change, 0 to destroy.
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 10-15 minutes. When complete, the URLs of the three load
balancers should be in the output, along with the bootstrap token for the Consul servers:

```shell
Apply complete! Resources: 248 added, 0 changed, 0 destroyed.

Outputs:

dc1_default_partition_apps = {
  "client" = {
    "consul_service_name" = "ecs-example-client-app"
    "lb_address" = "http://ecs-default-dc1-client-app-2080641086.us-west-2.elb.amazonaws.com:9090/ui"
    "lb_dns_name" = "ecs-default-dc1-client-app-2080641086.us-west-2.elb.amazonaws.com"
    "name" = "ecs-default-dc1-client-app"
    "port" = 9090
  }
  "ecs_cluster_arn" = "arn:aws:ecs:us-west-2:462181688919:cluster/ecs-dc1-default"
  "namespace" = "default"
  "partition" = "default"
  "region" = "us-west-2"
  "server" = {
    "consul_service_name" = "ecs-example-server-app"
    "name" = "ecs-default-dc1-example-server-app"
  }
}
dc1_part1_partition_apps = {
  "client" = {
    "consul_service_name" = "ecs-example-client-app"
    "lb_address" = "http://ecs-part-1-dc1-client-app-1797391975.us-west-2.elb.amazonaws.com:9090/ui"
    "lb_dns_name" = "ecs-part-1-dc1-client-app-1797391975.us-west-2.elb.amazonaws.com"
    "name" = "ecs-part-1-dc1-client-app"
    "port" = 9090
  }
  "ecs_cluster_arn" = "arn:aws:ecs:us-west-2:462181688919:cluster/ecs-dc1-part-1"
  "namespace" = "default"
  "partition" = "part-1"
  "region" = "us-west-2"
  "server" = {
    "consul_service_name" = "ecs-example-server-app"
    "name" = "ecs-part-1-dc1-example-server-app"
  }
}
dc1_server_bootstrap_token = <sensitive>
dc1_server_url = "http://ecs-dc1-consul-server-216568712.us-west-2.elb.amazonaws.com:8500"
dc2_default_partition_apps = {
  "client" = {
    "consul_service_name" = "ecs-example-client-app"
    "lb_address" = "http://ecs-default-dc2-client-app-1893675935.us-west-2.elb.amazonaws.com:9090/ui"
    "lb_dns_name" = "ecs-default-dc2-client-app-1893675935.us-west-2.elb.amazonaws.com"
    "name" = "ecs-default-dc2-client-app"
    "port" = 9090
  }
  "ecs_cluster_arn" = "arn:aws:ecs:us-west-2:462181688919:cluster/ecs-dc2-default"
  "namespace" = "default"
  "partition" = "default"
  "region" = "us-west-2"
  "server" = {
    "consul_service_name" = "ecs-example-server-app"
    "name" = "ecs-default-dc2-example-server-app"
  }
}
dc2_server_bootstrap_token = <sensitive>
dc2_server_url = "http://ecs-dc2-consul-server-1078624692.us-west-2.elb.amazonaws.com:8500"
```

### Explore

Get the bootstrap token for both the clusters from the Terraform output:

```console
$ terraform output -json | jq -r .dc1_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7

$ terraform output -json | jq -r .dc2_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-6f63da6882a7
```

If you click on the URL of the `dc1_server_url`, you should be able
to view the Consul UI and log in using the `dc1_server_bootstrap_token` above:

![Consul dc1 UI](../../_docs/sameness-dc1-ui.png?raw=true)

If you click on the `part-1` partition under the partitions dropdown, you should see the following UI:

![Consul dc1 part1 UI](../../_docs/sameness-dc1-part1-ui.png?raw=true)

If you click on the URL of the `dc2_server_url`, you should be able
to view the Consul UI and log in using the `dc2_server_bootstrap_token` above:

![Consul dc2 UI](../../_docs/sameness-dc2-ui.png?raw=true)

If you click on the Peers subsection in the left pane in `dc2_server_url` you should see that
a successful peering connection has been established with both the `default` and `part-1` partitions of the `dc1` cluster.

![Consul dc2 peering](../../_docs/sameness-peering-dc2.png?raw=true)

Similarly you should be able to see that `dc2-cluster` is a peer for `dc1`'s default and `part-1` partition from `dc1_server_url`. You should also see that the example server app in `dc2` is exported to both the partitions of `dc1` via the peering connection. This can be seen by clicking on the peer name in `dc1_server_url` under the `Peers` subsection.

![Consul dc1 exported service](../../_docs/sameness-exported-service-dc1.png?raw=true)

If you browse to the URL of the `client.lb_address` of the apps present in the terraform output, the example application UI should be displayed:

![Example App UI](../../_docs/sameness-client-ui.png?raw=true)

You should notice that all the client apps at this point will dial the server apps present in the same partition via their envoy sidecar. 

## Sameness Group illustration

We will now manually scaledown some of these server apps and visualize the changes to illustrate the failover usecases with Consul's service sameness groups. You can either try this manually by following the upcoming sections or run the `sameness-test` script to automate it.

With all the server apps functioning as expected, the calls from client apps should reach the server apps present in their local partition.

![Sameness Demo 1](../../_docs/sameness-demo-1.png?raw=true)

### Step 1

Manually scale down the server app present in DC1's `default` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC1_DEFAULT_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc1-example-server-app --desired-count 0
```

With the server app in the default partition scaled down to 0 tasks, the calls from the client app present in the DC1's default partition should failover to the server app present in DC1's `part-1` partition.

![Sameness Demo 2](../../_docs/sameness-demo-2.png?raw=true)

### Step 2

Manually scale down the server app present in DC1's `part-1` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC1_PART1_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc1-part-1-example-server-app --desired-count 0
```

With the server app in the `part-1` partition also scaled down to 0 tasks, the calls from the client app present in the DC1's `default` and `part-1` partition should failover to the server app present in DC2's `default` partition.

![Sameness Demo 3](../../_docs/sameness-demo-3.png?raw=true)

### Step 3

Manually scale up the server app present in DC1's `default` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC1_DEFAULT_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc1-example-server-app --desired-count 1
```

With the server app in DC1's `default` partition scaled up to run a single task, the calls from the client app present in the DC1's `default` partition should hit to the server app present in the local partition. Calls from the client app present in DC1's `part-1` partition should failover now to the server app present in DC1's `default` partition because failover happens in which the sameness group members are defined in the config entry for a single partition.

![Sameness Demo 4](../../_docs/sameness-demo-4.png?raw=true)

### Step 4

Manually scale down the server app present in DC2's `default` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC2_DEFAULT_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc2-example-server-app --desired-count 0
```

With the server app in the `default` partition of DC2 scaled down to 0 tasks, the calls from the client app present in the DC2's `default` partition should failover to the server app present in DC1's `default` partition.

![Sameness Demo 5](../../_docs/sameness-demo-5.png?raw=true)

### Step 5

Manually scale up the server app present in DC1's `part-1` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC1_PART1_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc1-part-1-example-server-app --desired-count 1
```

With the server app in DC1's `part-1` partition also scaled up to run a single task, the calls from the client app present in the DC1's `part-1` partition should hit to the server app present in the local (`part-1`) partition. Calls from the client app present in DC2's `default` partition should continue to failover to the server app present in DC1's `default` partition.

![Sameness Demo 6](../../_docs/sameness-demo-6.png?raw=true)

### Step 6

Manually scale up the server app present in DC2's `default` partition with the following command and wait for a few seconds for the change to propagate to Consul

```console
aws ecs update-service --region ${AWS_REGION} --cluster ${DC2_DEFAULT_PARTITION_ECS_CLUSTER_ARN} --service ecs-dc2-example-server-app --desired-count 1
```

Since all the partitions should have healthy instances of server apps running, the client apps should failover to hit the server apps present in their local partitions.

![Sameness Demo 7](../../_docs/sameness-demo-1.png?raw=true)

## Cleanup

Once you've finished testing, be sure to clean up the resources you've created:

```console
$ terraform destroy \
    -var name=${USER} \
    -var lb_ingress_ip=123.456.789.1
    -var-file=input.tfvars
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're
ready to deploy your own applications into the service mesh.
