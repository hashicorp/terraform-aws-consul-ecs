variable "additional_container_definitions" {
  description = "Additional container definitions to include in the task definition."
  # This is `any` on purpose. Using `list(any)` is too restrictive. It requires maps in the list to have the same key set, and same value types.
  type    = any
  default = []
}