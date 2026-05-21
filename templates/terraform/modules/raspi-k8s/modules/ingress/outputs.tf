output "name" {
  description = "Ingress resource name"
  value       = kubernetes_ingress_v1.this.metadata[0].name
}

output "namespace" {
  description = "Ingress namespace"
  value       = kubernetes_ingress_v1.this.metadata[0].namespace
}

output "host" {
  description = "Hostname configured for this Ingress"
  value       = var.host
}

output "tls_secret_name" {
  description = "Name of the TLS Secret (null when TLS is disabled)"
  value       = var.tls_enabled ? local.tls_secret_name : null
}

output "http_url" {
  description = "HTTP URL — add host entry pointing to any node IP"
  value       = "http://${var.host}:30080"
}

output "https_url" {
  description = "HTTPS URL (null when TLS is disabled)"
  value       = var.tls_enabled ? "https://${var.host}:30443" : null
}
