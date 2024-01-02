# Terminating Gateways on ECS.

This example demonstrates accessing non mesh destinations services from mesh tasks with the help of terminating gateways deployed as ECS tasks.

There are instructions below on how to interact with this setup.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/terminating-gateway-arch.png?raw=true)

## Requirements

* `jq`
* `curl`
* Terraform >= 1.2.2

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/terminating-gateway
```

This module contains everything needed to spin up the example. The only
requirement is to pass in the IP address of your workstation via the `lb_ingress_ip`
variable. This is used for the security groups on the application load balancers to ensure
only you have access to them.

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
    -var lb_ingress_ip=123.456.789.1
```

The plan should look similar to:

```shell
Plan: 96 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + consul_server_bootstrap_token = (known after apply)
  + consul_server_lb_address      = (known after apply)
  + mesh_client_lb_address        = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 7-10 minutes. When complete, the URLs of the three load
balancers should be in the output, along with the bootstrap token for the Consul servers:

```shell
Apply complete! Resources: 96 added, 0 changed, 0 destroyed.

Outputs:

consul_server_bootstrap_token = <sensitive>
consul_server_lb_address = "http://consul-ecs-consul-server-1772347952.us-east-1.elb.amazonaws.com:8500"
mesh_client_lb_address = "http://consul-ecs-example-client-app-111111111.us-east-1.elb.amazonaws.com:9090/ui"
```

### Explore

Get the bootstrap token for the Consul cluster from the Terraform output:

```console
$ terraform output -json | jq -r .consul_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7
```

If you click on the URL of the `consul_server_lb_address`, you should be able
to view the Consul UI and log in using the `consul_server_bootstrap_token` above:

![Consul dc1 UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/terminating-gateway-dc1.png?raw=true)

If you browse to the URL of the `mesh_client_lb_address`, you should see the following raw output in your browser

[Application UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/terminating-gateway-client-ui.png)

This indicates that the request from the client application that is part of the mesh was able to reach the external server application's task that is not part of the mesh with the help of the terminating gateway workload.

## Cleanup

Once you've finished testing, be sure to clean up the resources you've created:

```console
$ terraform destroy \
    -var lb_ingress_ip=123.456.789.1
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're
ready to deploy your own applications into the service mesh.
