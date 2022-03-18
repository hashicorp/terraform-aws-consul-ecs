# Admin Partitions

This folder provides an example of using the Admin Partition and Namespace support of Consul Enterprise.
- Consul Enterprise running on HashiCorp Cloud Platform
- Multiple AWS ECS clusters
- Tasks running on AWS Fargate
- A server service running in an ECS cluster scoped to an Admin Partition and Namespace
- A client service running in a separate ECS cluster scoped to a different Admin Partition and Namespace.
- Exported service config entries to expose the Admin Partition of the server to the client

