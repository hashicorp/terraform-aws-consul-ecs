# Consul WAN Federation with Mesh Gateways on ECS

This example demonstrates Consul cross datacenter WAN federation using mesh gateways on ECS.

There are instructions below on how to interact with Consul and test out some service mesh features.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mesh-gateways.png?raw=true)

## Requirements

* Terraform >= 1.2.2
* Authentication credentials for the [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication)

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/mesh-gateways
```

This module contains everything needed to spin up the example. The only
requirements are:
- You need to pass in the `name` variable. This value will be used as a unique identifier
  for all resources created by the example. The examples below use the name `ecs`.
- You need to pass in the IP address of your workstation via the `lb_ingress_ip`
  variable. This is used for the security groups on the elastic load balancers to ensure
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
    -var name=${USER} \
    -var lb_ingress_ip=123.456.789.1
```

The plan should look similar to:

```shell
Plan: 152 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + dc1_server_bootstrap_token   = (sensitive value)
  + dc2_server_bootstrap_token   = (sensitive value)
  + client_lb_address = (known after apply)
  + dc1_server_url    = (known after apply)
  + dc2_server_url    = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 5-7 minutes. When complete, the URLs of the three load
balancers should be in the output, along with the bootstrap token for the Consul servers:

```shell
Apply complete! Resources: 152 added, 0 changed, 0 destroyed.

Outputs:

dc1_server_bootstrap_token = <sensitive>
dc2_server_bootstrap_token = <sensitive>
client_lb_address = "http://ecs-dc1-example-client-app-111111111.us-east-1.elb.amazonaws.com:9090/ui"
dc1_server_url = "http://ecs-dc1-consul-server-111111111.us-east-1.elb.amazonaws.com:8500"
dc2_server_url = "http://ecs-dc2-consul-server-111111111.us-east-1.elb.amazonaws.com:8500"
```

### Explore

Get the `dc1_server_bootstrap_token` from the Terraform output:

```console
$ terraform output -json | jq -r .dc1_server_bootstrap_token.value
abcd1234-abcd-1234-abcd-123456789abcd
```

If you click on the URL of the `dc1_server_url`, you should be able
to view the Consul UI and log in using the `dc1_server_bootstrap_token` above:

![Consul dc1 UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mgw-dc1-consul-ui.png?raw=true)

~> At first, if you click on the URL of the `client_lb_address` or `dc1_server_url`,
the page might not load.
This is because the service mesh is not completely federated and heathy. It can take
between 6-8 minutes for the Consul datacenters to become fully federated.

Because the two Consul datacenters are WAN-federated via mesh gateways, you can browse the
catalog for `dc2` from the Consul UI in `dc1`. Select the dropdown list beside `dc1`
and select `dc2`. The Consul UI displays the service catalog for `dc2`.

![Consul dc2 UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mgw-dc2-consul-ui.png?raw=true)

If you browse to the URL of the `client_lb_address`, the example application UI should be displayed:

![Example App UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mgw-example-app.png?raw=true)

The `ecs-dc1-example-client-app` in `dc1` calls the `ecs-dc2-example-server-app` in `dc2` over the
WAN-federated Consul service mesh and shows the request path in the UI.

If you navigate to the same URL without `/ui`, the raw output is printed:

```json
{
  "name": "ecs-dc1-example-client-app",
  "uri": "/",
  "type": "HTTP",
  "ip_addresses": [
    "169.254.172.2",
    "10.0.2.181"
  ],
  "start_time": "2022-06-20T21:59:43.949338",
  "end_time": "2022-06-20T21:59:43.961535",
  "duration": "12.197198ms",
  "body": "Hello World",
  "upstream_calls": {
    "http://localhost:1234": {
      "name": "ecs-dc2-example-server-app",
      "uri": "http://localhost:1234",
      "type": "HTTP",
      "ip_addresses": [
        "169.254.172.2",
        "10.0.2.239"
      ],
      "start_time": "2022-06-20T21:59:43.960107",
      "end_time": "2022-06-20T21:59:43.960176",
      "duration": "68.958µs",
      "headers": {
        "Content-Length": "295",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Mon, 20 Jun 2022 21:59:43 GMT"
      },
      "body": "Hello World",
      "code": 200
    }
  },
  "code": 200
}
```

Under `upstream_calls`, you can see that the `ecs-dc1-example-client-app` is making
a call to uri `http://localhost:1234` which is returning with an HTTP code 200.

### Intentions

One of the features of Consul is its [Intentions](/docs/connect/intentions) system.
Intentions allow you to define rules dictating which services can communicate.

This installation has [ACLs](/docs/security/acl) enabled and by default
services are not allowed to communicate. Part of the configuration
in this module uses the [Consul Terraform provider](https://registry.terraform.io/providers/hashicorp/consul/latest/docs)
to [manage a service intention](./datacenters.tf#L89-L104) that allows
`ecs-dc1-example-client-app` to make requests to `ecs-dc2-example-server-app`.

We can change the intention to deny this traffic through the UI:

1. Click on the **Intentions** tab in the Consul UI.
1. Click the `ecs-dc1-example-client-app` row.
1. Click the **Deny** card.
1. Click the **Save** button.

![Intention UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mgw-intentions.png?raw=true)

Now, navigate to the UI of the example application. You should see something
that looks like:

![UI After Intention](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/mgw-ui-after-intention.png?raw=true)

The connection is red because the service mesh is no longer allowing `ecs-dc1-example-client-app` to 
make requests to `ecs-dc2-example-server-app`.

If you reset the intention back to **Allow** through the Consul UI, the traffic will flow again.

## Cleanup

Once you've finished testing, be sure to clean up the resources you've created:

```console
$ terraform destroy \
    -var name=${USER} \
    -var lb_ingress_ip=123.456.789.1
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're
ready to deploy your own applications into the service mesh.
