# Consul With Dev Server on ECS EC2 Example

This example module deploys a new VPC and ECS cluster and then provisions
a Consul dev server and two example service mesh tasks using the EC2 launch type.

## Requirements

* Terraform >= 0.14.0

## Usage

### Setup

Clone this repository:

```console
$ git clone https://github.com/hashicorp/terraform-aws-consul-ecs.git
$ cd terraform-aws-consul-ecs/examples/dev-server-ec2
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
