output "name" {
  description = "Namespace name"
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "id" {
  description = "Namespace resource ID"
  value       = kubernetes_namespace_v1.this.id
}
