output "service_account_name" {
  description = "ServiceAccount name"
  value       = kubernetes_service_account_v1.this.metadata[0].name
}

output "service_account_namespace" {
  description = "ServiceAccount namespace"
  value       = kubernetes_service_account_v1.this.metadata[0].namespace
}

output "role_name" {
  description = "Role or ClusterRole name (null when create_role = false)"
  value       = var.create_role ? local.role_name : null
}

output "binding_name" {
  description = "RoleBinding or ClusterRoleBinding name (null when create_role = false)"
  value = var.create_role ? (
    var.cluster_scoped
    ? kubernetes_cluster_role_binding_v1.this[0].metadata[0].name
    : kubernetes_role_binding_v1.this[0].metadata[0].name
  ) : null
}
