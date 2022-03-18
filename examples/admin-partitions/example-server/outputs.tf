output "upstream_name" {
  value = "example_server_${local.suffix}"
}

output "upstream_partition" {
  value = var.partition
}

output "upstream_namespace" {
  value = var.namespace
}
