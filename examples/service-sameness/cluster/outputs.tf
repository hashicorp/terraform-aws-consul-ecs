# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "ecs_cluster" {
  value = aws_ecs_cluster.this
}

output "log_group" {
  value = aws_cloudwatch_log_group.log_group
}