output "namespace" {
  description = "Namespace the application is deployed into"
  value       = local.namespace
}

output "deployment_name" {
  description = "Name of the Kubernetes Deployment"
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes Service"
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "node_ports" {
  description = "Map of port name → NodePort number (empty when service_type != NodePort)"
  value = var.service_type == "NodePort" ? {
    for p in kubernetes_service_v1.this.spec[0].port : p.name => p.node_port
  } : {}
}

output "cluster_ip" {
  description = "ClusterIP assigned to the Service"
  value       = kubernetes_service_v1.this.spec[0].cluster_ip
}
