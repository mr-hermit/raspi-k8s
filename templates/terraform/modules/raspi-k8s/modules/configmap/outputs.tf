output "name" {
  description = "ConfigMap name"
  value       = kubernetes_config_map_v1.this.metadata[0].name
}

output "namespace" {
  description = "ConfigMap namespace"
  value       = kubernetes_config_map_v1.this.metadata[0].namespace
}
