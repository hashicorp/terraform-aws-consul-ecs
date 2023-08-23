# Consul With Dev Server on Fargate Example

This example module deploys a new VPC and ECS cluster and then provisions
a Consul dev server and two example service mesh tasks using Fargate.

There are then instructions on how to interact with Consul and test out
some service mesh features.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/dev-server-fargate.png?raw=true)

## Requirements

* Terraform >= 0.14.0

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/dev-server-fargate
```

This module contains everything needed to spin up the example. The only
requirement is that you pass in the IP address of your workstation via the `lb_ingress_ip`
variable. This is used for the security group on the two load balancers to ensure
only you have access to them since Consul is not running in a secure configuration.

First, determine your public IP. You can use a site like https://ifconfig.me/:

```console
$ curl ifconfig.me
123.456.789.1%
```

Initialize Terraform:

```console
$ terraform init
```

### Terraform Apply

Then apply the Terraform and pass in your IP:

```console
$ terraform apply -var lb_ingress_ip=123.456.789.1
```

The plan should look similar to:

```shell
Plan: 46 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + consul_server_lb_address = (known after apply)
  + mesh_client_lb_address   = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 2-5 minutes. When complete, the URLs of the two load
balancers should be in the output:

```shell
Apply complete! Resources: 46 added, 0 changed, 0 destroyed.

Outputs:

consul_server_lb_address = "http://consul-ecs-consul-server-111111111.us-east-1.elb.amazonaws.com:8500"
mesh_client_lb_address = "http://consul-ecs-example-client-app-111111111.us-east-1.elb.amazonaws.com:9090/ui"
```

### Explore

If you click on the URL of the `consul_server_lb_address`, you should be able
to view the Consul UI:

![Consul UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/consul-ui.png?raw=true)

~> At first, if you click on the URL of the `mesh_client_lb_address` or `consul_server_lb_address`,
the page might not load.
This is because the example client application or the Consul server are not yet healthy. After
a minute or two, you should be able to load the UI.

If you go the URL of the `mesh_client_lb_address` in your browser, you should see the UI:

![Example App UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/example-app.png?raw=true)

The `consul-ecs-example-client-app` calls the `consul-ecs-example-server-app` through the service mesh
and shows the request path in the UI.

If you navigate to the same URL without `/ui`, you'll see the raw requests:

```json
{
  "name": "consul-ecs-example-client-app",
  "uri": "/",
  "type": "HTTP",
  "ip_addresses": [
    "169.254.172.2",
    "10.0.2.197"
  ],
  "start_time": "2021-05-26T17:18:50.577783",
  "end_time": "2021-05-26T17:18:50.581168",
  "duration": "3.384384ms",
  "body": "Hello World",
  "upstream_calls": {
    "http://localhost:1234": {
      "name": "consul-ecs-example-server-app",
      "uri": "http://localhost:1234",
      "type": "HTTP",
      "ip_addresses": [
        "169.254.172.2",
        "10.0.2.168"
      ],
      "start_time": "2021-05-26T17:18:50.580468",
      "end_time": "2021-05-26T17:18:50.580550",
      "duration": "82.636µs",
      "headers": {
        "Content-Length": "298",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Wed, 26 May 2021 17:18:50 GMT"
      },
      "body": "Hello World",
      "code": 200
    }
  },
  "code": 200
}
```

Under `upstream_calls`, you can see that the `consul-ecs-example-client-app` is making
a call to uri `http://localhost:1234` which is returning with an HTTP code 200.

### Intentions

One of the features of Consul is its [Intentions](/docs/connect/intentions) system.
Intentions allow you to define rules dictating which services can communicate.

Because this installation does not have [ACLs](/docs/security/acl) enabled, by
default all services are allowed to communicate. That's why `consul-ecs-example-client-app`
can make requests to `consul-ecs-example-server-app`.

We can create a deny intention to deny this traffic through the UI:

1. Click on the **Intentions** tab in the Consul UI.
1. Click the **Create** button.
1. In the **Source Service** drop-down, select `consul-ecs-example-client-app`.
1. In the **Destination Service** drop-down, select `consul-ecs-example-server-app`.
1. Click the **Deny** card.
1. Click the **Save** button.

![Intention UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/intentions.png?raw=true)

Now, navigate to the UI of the example application. You should see something
that looks like:

![UI After Intention](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/ui-after-intention.png?raw=true)

The connection is red because the service mesh is no longer allowing `consul-ecs-example-client-app` to 
make requests to `consul-ecs-example-server-app`.

If you delete the intention through the Consul UI, the traffic should flow again.

## Cleanup

Once you've done testing, be sure to clean up the resources you've created:

```console
$ terraform destroy -var lb_ingress_ip=123.456.789.1
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're ready to deploy your own applications
into the service mesh.
