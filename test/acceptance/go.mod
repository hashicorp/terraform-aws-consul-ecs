module github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance

go 1.15

require (
	github.com/aws/aws-sdk-go-v2/service/ecs v1.9.1
	github.com/gruntwork-io/terratest v0.34.6
	github.com/hashicorp/consul/api v1.11.0
	github.com/hashicorp/consul/sdk v0.8.0
	github.com/stretchr/testify v1.7.0
)
