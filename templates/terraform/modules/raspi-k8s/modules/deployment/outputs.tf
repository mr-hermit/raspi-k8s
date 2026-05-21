output "name" {
  description = "Deployment name"
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "namespace" {
  description = "Deployment namespace"
  value       = kubernetes_deployment_v1.this.metadata[0].namespace
}

output "uid" {
  description = "Deployment UID"
  value       = kubernetes_deployment_v1.this.metadata[0].uid
}

output "selector_labels" {
  description = "Pod selector labels — use as the service selector"
  value       = local.selector_labels
}

output "labels" {
  description = "Full set of labels applied to the Deployment and pods"
  value       = local.base_labels
}
