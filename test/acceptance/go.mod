module github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance

go 1.15

require (
	github.com/aws/aws-sdk-go-v2/config v1.15.9
	github.com/aws/aws-sdk-go-v2/service/ecs v1.9.1
	github.com/aws/aws-sdk-go-v2/service/iam v1.18.5
	github.com/gruntwork-io/terratest v0.34.6
	github.com/hashicorp/consul/api v1.12.0
	github.com/hashicorp/consul/sdk v0.9.0
	github.com/hashicorp/lint-consul-retry v1.2.0 // indirect
	github.com/stretchr/testify v1.4.0
)
