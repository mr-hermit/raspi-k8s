output "name" {
  description = "Secret name"
  value       = kubernetes_secret_v1.this.metadata[0].name
}

output "namespace" {
  description = "Secret namespace"
  value       = kubernetes_secret_v1.this.metadata[0].namespace
}
