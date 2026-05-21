output "name" {
  description = "Certificate resource name"
  value       = var.name
}

output "namespace" {
  description = "Certificate namespace"
  value       = var.namespace
}

output "secret_name" {
  description = "Name of the Kubernetes Secret containing the issued certificate"
  value       = var.secret_name
}
