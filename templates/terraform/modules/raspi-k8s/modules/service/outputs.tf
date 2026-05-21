output "name" {
  description = "Service name"
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "namespace" {
  description = "Service namespace"
  value       = kubernetes_service_v1.this.metadata[0].namespace
}

output "cluster_ip" {
  description = "ClusterIP assigned to the Service"
  value       = kubernetes_service_v1.this.spec[0].cluster_ip
}

output "node_ports" {
  description = "Map of port name to assigned NodePort number (populated only for NodePort services)"
  value = {
    for p in kubernetes_service_v1.this.spec[0].port : p.name => p.node_port
  }
}
