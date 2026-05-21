output "namespace" {
  description = "Namespace all resources were deployed into"
  value       = local.namespace
}

output "deployment_name" {
  description = "Deployment resource name"
  value       = module.deployment.name
}

output "selector_labels" {
  description = "Pod selector labels — use to target this deployment from other resources"
  value       = module.deployment.selector_labels
}

output "service_name" {
  description = "Service resource name"
  value       = module.service.name
}

output "service_cluster_ip" {
  description = "ClusterIP assigned to the Service"
  value       = module.service.cluster_ip
}

output "node_ports" {
  description = "Map of port name to NodePort number (populated only when service_type = NodePort)"
  value       = module.service.node_ports
}

output "pvc_name" {
  description = "PVC name (null when storage_enabled = false)"
  value       = local.pvc_name
}

output "ingress_host" {
  description = "Ingress hostname (null when ingress_enabled = false)"
  value       = var.ingress_enabled ? module.ingress[0].host : null
}

output "ingress_http_url" {
  description = "Ingress HTTP URL — requires a hosts-file or DNS entry pointing to any node IP"
  value       = var.ingress_enabled ? module.ingress[0].http_url : null
}

output "ingress_https_url" {
  description = "Ingress HTTPS URL (null when TLS is disabled or ingress is disabled)"
  value       = var.ingress_enabled && var.ingress_tls_enabled ? module.ingress[0].https_url : null
}
