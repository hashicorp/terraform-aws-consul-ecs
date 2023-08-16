# Peering of Consul clusters via Mesh gateways on ECS.

This example demonstrates peering of two Consul clusters using mesh gateways on ECS.

There are instructions below on how to interact with Consul and test out some service mesh features.

![Example architecture](../../_docs/peering-arch.png?raw=true)

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
$ cd terraform-aws-consul-ecs/examples/cluster-peering
```

This module contains everything needed to spin up the example. The only
requirements are:
- You need to pass in the `name` variable. This value will be used as a unique identifier
  for all resources created by the example. The examples below use the name `con`.
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
Plan: 166 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + client_lb_address          = (known after apply)
  + dc1_server_bootstrap_token = (sensitive value)
  + dc1_server_url             = (known after apply)
  + dc2_server_bootstrap_token = (sensitive value)
  + dc2_server_url             = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 7-10 minutes. When complete, the URLs of the three load
balancers should be in the output, along with the bootstrap token for the Consul servers:

```shell
Apply complete! Resources: 166 added, 0 changed, 0 destroyed.

Outputs:

client_lb_address = "http://con-dc1-example-client-app-1896933827.us-west-2.elb.amazonaws.com:9090/ui"
dc1_server_bootstrap_token = <sensitive>
dc1_server_url = "http://con-dc1-consul-server-87966086.us-west-2.elb.amazonaws.com:8500"
dc2_server_bootstrap_token = <sensitive>
dc2_server_url = "http://con-dc2-consul-server-17611657.us-west-2.elb.amazonaws.com:8500"
```

### Explore

Get the bootstrap token for both the clusters from the Terraform output:

```console
$ terraform output -json | jq -r .dc1_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7

$ terraform output -json | jq -r .dc2_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7
```

If you click on the URL of the `dc1_server_url`, you should be able
to view the Consul UI and log in using the `dc1_server_bootstrap_token` above:

![Consul dc1 UI](../../_docs/peering-dc1-ui.png?raw=true)

If you click on the URL of the `dc2_server_url`, you should be able
to view the Consul UI and log in using the `dc2_server_bootstrap_token` above:

![Consul dc2 UI](../../_docs/peering-dc2-ui.png?raw=true)

If you click on the Peers subsection in the left pane in `dc1_server_url` you should see that
a successful peering connection has been established with the `dc2` cluster.

![Consul dc2 peering](../../_docs/peering-established.png?raw=true)

Similarly you should be able to see that `dc1-cluster` is a peer for `dc2` from `dc2_server_url`. You should also see that the example server app is exported to `dc1` via the peering connection. This can be seen by clicking on the peer name in `dc2_server_url` under the `Peers` subsection.

![Consul dc2 exported service](../../_docs/peering-exported-service.png?raw=true)

You should see an intention configured for the example server app service in `dc2` for allowing calls from the client app present in the peer `dc1-cluster`.

![Consul peering intention](../../_docs/peering-intention.png?raw=true)

If you browse to the URL of the `client_lb_address`, the example application UI should be displayed:

![Example App UI](../../_docs/peering-successful.png?raw=true)

If you navigate to the same URL without `/ui`, the raw output is printed:

```json
{
  "name": "con-dc1-example-client-app",
  "uri": "/",
  "type": "HTTP",
  "ip_addresses": [
    "169.254.172.2",
    "10.0.2.212"
  ],
  "start_time": "2023-08-08T09:47:51.537260",
  "end_time": "2023-08-08T09:47:51.549336",
  "duration": "12.075392ms",
  "body": "Hello World",
  "upstream_calls": {
    "http://localhost:1234": {
      "name": "con-dc2-example-server-app",
      "uri": "http://localhost:1234",
      "type": "HTTP",
      "ip_addresses": [
        "169.254.172.2",
        "10.0.2.86"
      ],
      "start_time": "2023-08-08T09:47:51.547575",
      "end_time": "2023-08-08T09:47:51.547740",
      "duration": "165.093µs",
      "headers": {
        "Content-Length": "295",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Tue, 08 Aug 2023 09:47:51 GMT"
      },
      "body": "Hello World",
      "code": 200
    }
  },
  "code": 200
}
```

Under `upstream_calls`, you can see that the `con-dc1-example-client-app` is making
a call to uri `http://localhost:1234` which is returning with an HTTP code 200.

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
