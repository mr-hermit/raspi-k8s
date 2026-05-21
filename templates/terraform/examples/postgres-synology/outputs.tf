output "namespace" {
  description = "Namespace used by this example"
  value       = var.namespace
}

output "postgres_service_name" {
  description = "Service name for postgres"
  value       = module.postgres.service_name
}

output "postgres_pvc_name" {
  description = "Synology-backed PVC name used by postgres"
  value       = module.postgres.pvc_name
}
