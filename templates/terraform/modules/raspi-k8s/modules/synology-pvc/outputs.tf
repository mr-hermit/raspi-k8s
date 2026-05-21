output "name" {
  description = "PVC name"
  value       = kubernetes_persistent_volume_claim_v1.this.metadata[0].name
}

output "namespace" {
  description = "PVC namespace"
  value       = kubernetes_persistent_volume_claim_v1.this.metadata[0].namespace
}

output "storage_class_name" {
  description = "StorageClass used by this PVC"
  value       = var.storage_class_name
}
