# API Gateways on ECS.

This example demonstrates accessing mesh tasks present in ECS via Consul API gateways. The API gateway workload in this module is deployed as a task in ECS.

There are instructions below on how to interact with this setup and test out some of the features that Consul API gateways offer.

![Example architecture](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/api-gateway-arch.png?raw=true)

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
$ cd terraform-aws-consul-ecs/examples/api-gateway
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
Plan: 117 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + api_gateway_lb_url            = (known after apply)
  + consul_server_bootstrap_token = (sensitive value)
  + consul_server_lb_address      = (known after apply)
```

Type `yes` to apply the changes.

~> **Warning:** These resources will cost money. Be sure to run `terraform destroy`
   when you've finished testing.

The apply should take 7-10 minutes. When complete, the URLs of the three load
balancers should be in the output, along with the bootstrap token for the Consul servers:

```shell
Apply complete! Resources: 117 added, 0 changed, 0 destroyed.

Outputs:

api_gateway_lb_url = "http://consul-ecs-api-gateway-605393728.us-east-1.elb.amazonaws.com:8443"
consul_server_bootstrap_token = <sensitive>
consul_server_lb_address = "http://consul-ecs-consul-server-1772347952.us-east-1.elb.amazonaws.com:8500"
```

### Explore

Get the bootstrap token for the Consul cluster from the Terraform output:

```console
$ terraform output -json | jq -r .consul_server_bootstrap_token.value
e2cb39e2-b9fd-18af-025f-86f6da6889a7
```

If you click on the URL of the `consul_server_lb_address`, you should be able
to view the Consul UI and log in using the `consul_server_bootstrap_token` above:

![Consul dc1 UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/api-gateway-dc1.png?raw=true)

If you browse to the URL of the `api_gateway_lb_url`, you should see the following raw output in your browser

```json
{
  "name": "consul-ecs-example-client-app",
  "uri": "/",
  "type": "HTTP",
  "ip_addresses": [
    "169.254.172.2",
    "10.0.2.26"
  ],
  "start_time": "2023-12-05T08:41:56.567158",
  "end_time": "2023-12-05T08:41:56.649110",
  "duration": "81.952058ms",
  "body": "Hello World",
  "upstream_calls": {
    "http://localhost:1234": {
      "name": "consul-ecs-example-server-app",
      "uri": "http://localhost:1234",
      "type": "HTTP",
      "ip_addresses": [
        "169.254.172.2",
        "10.0.1.250"
      ],
      "start_time": "2023-12-05T08:41:56.647444",
      "end_time": "2023-12-05T08:41:56.647733",
      "duration": "289.312µs",
      "headers": {
        "Content-Length": "299",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Tue, 05 Dec 2023 08:41:56 GMT",
        "Server": "envoy",
        "X-Envoy-Upstream-Service-Time": "78"
      },
      "body": "Hello World",
      "code": 200
    }
  },
  "code": 200
}
```

Under `upstream_calls`, you can see that the `consul-ecs-example-client-app` is making
a call to uri `http://localhost:1234` which is returning with an HTTP code 200. This indicates that we could access the client application sitting inside the mesh via the API gateway.

If you suffix the URL of `api_gateway_lb_url` with the path `/ui`, you should see the application's UI as shown below

[Application UI](https://github.com/hashicorp/terraform-aws-consul-ecs/blob/main/_docs/api-gateway-client-ui.png?raw=true)

### Using API gateway as a load balancer

Consul API gateways can also be used to perform weighted load balancing between replicas of a single application. The terraform script deploys two additional identical applications `echo-app-one` and `echo-app-two`. If you suffix the URL of `api_gateway_lb_url` with the path `/echo`, the API gateway directs traffic to either `echo-app-one` or `echo-app-two`. A sample response looks something like

```json
{
 "path": "/echo",
 "host": "consul-ecs-api-gateway-605393728.us-east-1.elb.amazonaws.com:8443",
 "method": "GET",
 "proto": "HTTP/1.1",
 "headers": {
  "Accept": [
   "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
  ],
  "Accept-Encoding": [
   "gzip, deflate"
  ],
  "Accept-Language": [
   "en-GB,en-US;q=0.9,en;q=0.8"
  ],
  "Upgrade-Insecure-Requests": [
   "1"
  ],
  "User-Agent": [
   "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
  ],
  "X-Amzn-Trace-Id": [
   "Root=1-656ee395-5e2adc002dc65d8b40cf359c"
  ],
  "X-Envoy-Expected-Rq-Timeout-Ms": [
   "15000"
  ],
  "X-Forwarded-Client-Cert": [
   "By=spiffe://6750841e-46e2-3c46-d21f-5c023335d268.consul/ns/default/dc/dc1/svc/echo-app-one;Hash=f63990ef94a1501fb699de32292cd8d884b60e2f52487cd4b88f4d53d4fff46f;Cert=\"-----BEGIN%20CERTIFICATE-----%0AMIICLDCCAdGgAwIBAgIBETAKBggqhkjOPQQDAjAwMS4wLAYDVQQDEyVwcmktMXY4%0AZWs5ZC5jb25zdWwuY2EuNjc1MDg0MWUuY29uc3VsMB4XDTIzMTIwNTA2NTAxOVoX%0ADTIzMTIwODA2NTAxOVowADBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABPZMFWsY%0Ak7WQysKkEcNF%2Bk3vDjgBtIbFk%2F%2FA5uvRaIXcGpvjKN05o3IqyNT8ozMqhqp5O3n5%0An1jidAglOdrr95yjggEKMIIBBjAOBgNVHQ8BAf8EBAMCA7gwHQYDVR0lBBYwFAYI%0AKwYBBQUHAwIGCCsGAQUFBwMBMAwGA1UdEwEB%2FwQCMAAwKQYDVR0OBCIEIJUvA5Vl%0AbBZFdzho1WhjR7RbdQkaNdyXhQR%2FpJyljbaxMCsGA1UdIwQkMCKAIN9J26wEKBFi%0AERZDYTwRgIrZFsJTcB5i2Jmca%2FUvpq4DMG8GA1UdEQEB%2FwRlMGOGYXNwaWZmZTov%0ALzY3NTA4NDFlLTQ2ZTItM2M0Ni1kMjFmLTVjMDIzMzM1ZDI2OC5jb25zdWwvbnMv%0AZGVmYXVsdC9kYy9kYzEvc3ZjL2NvbnN1bC1lY3MtYXBpLWdhdGV3YXkwCgYIKoZI%0Azj0EAwIDSQAwRgIhAPekqGpS9L2a%2B4kmWqjZYJmOWyFkt%2B1Uewl1vz9%2BHhK5AiEA%0Ag%2BhBZKov8%2FDxZSgQJUs2sBxkEijh3EOuPp4ADL8zX%2Bc%3D%0A-----END%20CERTIFICATE-----%0A\";Chain=\"-----BEGIN%20CERTIFICATE-----%0AMIICLDCCAdGgAwIBAgIBETAKBggqhkjOPQQDAjAwMS4wLAYDVQQDEyVwcmktMXY4%0AZWs5ZC5jb25zdWwuY2EuNjc1MDg0MWUuY29uc3VsMB4XDTIzMTIwNTA2NTAxOVoX%0ADTIzMTIwODA2NTAxOVowADBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABPZMFWsY%0Ak7WQysKkEcNF%2Bk3vDjgBtIbFk%2F%2FA5uvRaIXcGpvjKN05o3IqyNT8ozMqhqp5O3n5%0An1jidAglOdrr95yjggEKMIIBBjAOBgNVHQ8BAf8EBAMCA7gwHQYDVR0lBBYwFAYI%0AKwYBBQUHAwIGCCsGAQUFBwMBMAwGA1UdEwEB%2FwQCMAAwKQYDVR0OBCIEIJUvA5Vl%0AbBZFdzho1WhjR7RbdQkaNdyXhQR%2FpJyljbaxMCsGA1UdIwQkMCKAIN9J26wEKBFi%0AERZDYTwRgIrZFsJTcB5i2Jmca%2FUvpq4DMG8GA1UdEQEB%2FwRlMGOGYXNwaWZmZTov%0ALzY3NTA4NDFlLTQ2ZTItM2M0Ni1kMjFmLTVjMDIzMzM1ZDI2OC5jb25zdWwvbnMv%0AZGVmYXVsdC9kYy9kYzEvc3ZjL2NvbnN1bC1lY3MtYXBpLWdhdGV3YXkwCgYIKoZI%0Azj0EAwIDSQAwRgIhAPekqGpS9L2a%2B4kmWqjZYJmOWyFkt%2B1Uewl1vz9%2BHhK5AiEA%0Ag%2BhBZKov8%2FDxZSgQJUs2sBxkEijh3EOuPp4ADL8zX%2Bc%3D%0A-----END%20CERTIFICATE-----%0A\";Subject=\"\";URI=spiffe://6750841e-46e2-3c46-d21f-5c023335d268.consul/ns/default/dc/dc1/svc/consul-ecs-api-gateway"
  ],
  "X-Forwarded-For": [
   "117.206.124.170"
  ],
  "X-Forwarded-Port": [
   "8443"
  ],
  "X-Forwarded-Proto": [
   "http"
  ],
  "X-Request-Id": [
   "cd54c8d5-4e8f-4bff-8afe-73b6bdd867ca"
  ]
 },
 "namespace": "",
 "ingress": "",
 "service": "echo-app-one",
 "pod": ""
}
```

You could see that the requests get load balanced between the two service instances with the following command

```bash
api-gateway > for i in {1..10}; do curl -s http://consul-ecs-api-gateway-605393728.us-east-1.elb.amazonaws.com:8443/echo | jq .service; done
"echo-app-two"
"echo-app-two"
"echo-app-two"
"echo-app-two"
"echo-app-two"
"echo-app-two"
"echo-app-one"
"echo-app-one"
"echo-app-one"
"echo-app-one"
```


## Cleanup

Once you've finished testing, be sure to clean up the resources you've created:

```console
$ terraform destroy \
    -var lb_ingress_ip=123.456.789.1
```

## Next Steps

Next, see our [full documentation](https://www.consul.io/docs/ecs) when you're
ready to deploy your own applications into the service mesh.
