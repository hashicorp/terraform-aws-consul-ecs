# EC2 with transparent proxy

This example module deploys a new VPC and ECS cluster and then provisions
a Consul dev server and two example service mesh tasks using the EC2 launch type and verifies if services are able to communicate each other via transparent proxy. [Transparent proxy](https://developer.hashicorp.com/consul/docs/k8s/connect/transparent-proxy) is how Consul automatically redirects outbound traffic from a container to the Envoy sidecar present within the same task thus disallowing users to directly hit the upstream endpoints without passing through the proxy. Note that transparent proxy is only supported for the ECS EC2 launch type.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/dev-server-ec2.png?raw=true)

## Requirements

* Terraform >= 0.14.0

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ git checkout tags/<latest-version>
$ cd terraform-aws-consul-ecs/examples/dev-server-ec2-transparent-proxy
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
Plan: 82 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + consul_server_lb_address = (known after apply)
  + consul_server_bootstrap_token = (sensitive value)
  + mesh_client_lb_address   = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 2-5 minutes. When complete, the URLs of the two load
balancers should be in the output:

```shell
Apply complete! Resources: 82 added, 0 changed, 0 destroyed.

Outputs:

consul_server_lb_address = "http://consul-ecs-consul-server-111111111.us-east-1.elb.amazonaws.com:8500"
consul_server_bootstrap_token = <sensitive>
mesh_client_lb_address = "http://consul-ecs-example-client-app-111111111.us-east-1.elb.amazonaws.com:9090/ui"
```

### Explore

If you click on the URL of the `consul_server_lb_address`, you should be able
to view the Consul UI:

![Consul UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/consul-ui.png?raw=true)

You should be able to login to Consul with the `consul_server_bootstrap_token`.

~> At first, if you click on the URL of the `mesh_client_lb_address` or `consul_server_lb_address`,
the page might not load.
This is because the example client application or the Consul server are not yet healthy. After
a minute or two, you should be able to load the UI.

If you go the URL of the `mesh_client_lb_address` in your browser, you should see the UI:

![Example App UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/ec2-transparent-proxy-ui.png?raw=true)

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
    "10.0.1.237"
  ],
  "start_time": "2024-01-18T17:09:20.908239",
  "end_time": "2024-01-18T17:09:20.963856",
  "duration": "55.616609ms",
  "body": "Hello World",
  "upstream_calls": {
    "http://consul-ecs-example-server-app.virtual.consul": {
      "name": "consul-ecs-example-server-app",
      "uri": "http://consul-ecs-example-server-app.virtual.consul",
      "type": "HTTP",
      "ip_addresses": [
        "123.234.456.210",
        "10.0.3.91"
      ],
      "start_time": "2024-01-18T17:09:20.958409",
      "end_time": "2024-01-18T17:09:20.958544",
      "duration": "135.381µs",
      "headers": {
        "Content-Length": "298",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Thu, 18 Jan 2024 17:09:20 GMT"
      },
      "body": "Hello World",
      "code": 200
    }
  },
  "code": 200
}
```

Under `upstream_calls`, you can see that the `consul-ecs-example-client-app` is making
a call to uri `http://consul-ecs-example-server-app.virtual.consul`. Internally the DNS resolve request gets transparently routed to Consul Dataplane's DNS proxy server and gets resolved to a virtual IP of the `consul-ecs-example-server-app` service which is present in Consul's catalog. After that the request gets transparently proxied through the client app's sidecar and reaches the server app's sidecar before reaching the server app's container.

### (optional) SSH Access to Container Instances

This module supports creating a bastion server (or jump host) which allows you 
to login to container instances in EC2 over SSH. This uses the `lb_ingress_ip` to 
configure a security group so that only you have access to the bastion instance.
You will need an SSH keypair on your local machine.

To have this module create the bastion server, pass the `public_ssh_key` variable:

```console
$ terraform apply -var lb_ingress_ip=123.456.789.1 -var public_ssh_key=~/.ssh/id_rsa.pub
```

You should see a `bastion_ip` in the Terraform outputs:

```shell
Outputs:

bastion_ip = "1.2.3.4"
consul_server_lb_address = "http://consul-ecs-consul-server-111111111.us-east-1.elb.amazonaws.com:8500"
mesh_client_lb_address = "http://consul-ecs-example-client-app-111111111.us-east-1.elb.amazonaws.com:9090/ui"
```

To login to a container instance, specify the bastion as a jump host using `ssh -J`.
For example, if the bastion IP is 1.2.3.4 and a container instance is at 10.0.1.2:

```shell
ssh -J 'ec2-user@1.2.3.4' 'ec2-user@10.0.1.2'
```

### Explore

To explore Consul and the sample application, see the [Fargate Example README](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/examples/dev-server-fargate/README.md#explore).

## Cleanup

Once you've done testing, be sure to clean up the resources you've created:

```console
$ terraform destroy -var lb_ingress_ip=123.456.789.1
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're ready to deploy your own applications
into the service mesh.
