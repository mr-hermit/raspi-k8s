variable "service_account_name" {
  description = "Name of the ServiceAccount to create"
  type        = string
}

variable "namespace" {
  description = "Namespace for the ServiceAccount and (when cluster_scoped = false) the Role/RoleBinding"
  type        = string
}

variable "automount_token" {
  description = "Whether to automatically mount the ServiceAccount token in pods. Disable when not needed."
  type        = bool
  default     = false
}

variable "create_role" {
  description = "Whether to create a Role (or ClusterRole when cluster_scoped = true) and bind it to the ServiceAccount"
  type        = bool
  default     = true
}

variable "cluster_scoped" {
  description = "When true, creates a ClusterRole + ClusterRoleBinding instead of namespace-scoped Role + RoleBinding"
  type        = bool
  default     = false
}

variable "role_name" {
  description = "Name of the Role or ClusterRole. Defaults to service_account_name when null."
  type        = string
  default     = null
}

variable "rules" {
  description = "RBAC policy rules to include in the Role or ClusterRole"
  type = list(object({
    api_groups = list(string)
    resources  = list(string)
    verbs      = list(string)
  }))
  default = []
}

variable "labels" {
  description = "Labels applied to all RBAC resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations applied to the ServiceAccount"
  type        = map(string)
  default     = {}
}
