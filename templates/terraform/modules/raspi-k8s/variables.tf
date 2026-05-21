# ── Identity ──────────────────────────────────────────────────────────────────

variable "app_name" {
  description = "Application name — used for resource naming and the 'app' selector label"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether to create the namespace. Set false when the namespace already exists."
  type        = bool
  default     = false
}

variable "namespace_labels" {
  description = "Extra labels for the namespace (used only when create_namespace = true)"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Extra labels applied to all resources created by this module"
  type        = map(string)
  default     = {}
}

# ── Container image ───────────────────────────────────────────────────────────

variable "image" {
  description = "Container image reference. Use rasserv01:30500/<name>:<tag> or the raspi/ short alias."
  type        = string
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "command" {
  description = "Override container entrypoint"
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Override container arguments"
  type        = list(string)
  default     = []
}

# ── Ports ─────────────────────────────────────────────────────────────────────

variable "ports" {
  description = <<-EOT
    Combined port definitions used for both the container and the Service.

    - container_port: port the application listens on inside the container
    - service_port:   port exposed by the Service (defaults to container_port)
    - node_port:      NodePort number (30000-32767, required when service_type = NodePort)
  EOT
  type = list(object({
    name           = string
    container_port = number
    service_port   = optional(number, null)
    node_port      = optional(number, null)
    protocol       = optional(string, "TCP")
  }))
  default = []
}

# ── Environment ───────────────────────────────────────────────────────────────

variable "env" {
  description = "Plain key-value environment variables"
  type        = map(string)
  default     = {}
}

variable "env_from_configmaps" {
  description = "ConfigMap names whose keys are injected as env vars"
  type        = list(string)
  default     = []
}

variable "env_from_secrets" {
  description = "Secret names whose keys are injected as env vars"
  type        = list(string)
  default     = []
}

# ── Resources ─────────────────────────────────────────────────────────────────

variable "resources_requests_cpu" {
  description = "CPU request — keep conservative on Pi hardware (e.g. 50m, 100m)"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request"
  type        = string
  default     = "128Mi"
}

variable "resources_limits_memory" {
  description = "Memory limit"
  type        = string
  default     = "256Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit (null = no limit; recommended for bursty workloads on Pi)"
  type        = string
  default     = null
}

# ── Health checks ─────────────────────────────────────────────────────────────

variable "liveness_probe_http_path" {
  description = "HTTP path for liveness probe (e.g. /healthz). Null = disabled."
  type        = string
  default     = null
}

variable "liveness_probe_http_port" {
  description = "Port for liveness HTTP probe"
  type        = number
  default     = null
}

variable "readiness_probe_http_path" {
  description = "HTTP path for readiness probe. Null = disabled."
  type        = string
  default     = null
}

variable "readiness_probe_http_port" {
  description = "Port for readiness HTTP probe"
  type        = number
  default     = null
}

# ── Service ───────────────────────────────────────────────────────────────────

variable "service_type" {
  description = "Kubernetes Service type: ClusterIP or NodePort"
  type        = string
  default     = "ClusterIP"
}

# ── Ingress ───────────────────────────────────────────────────────────────────

variable "ingress_enabled" {
  description = "Whether to create an nginx Ingress rule for this application"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for the Ingress rule (e.g. my-app.local). Required when ingress_enabled = true."
  type        = string
  default     = null
}

variable "ingress_path" {
  description = "URL path prefix routed to the Service"
  type        = string
  default     = "/"
}

variable "ingress_service_port" {
  description = "Service port that Ingress routes to. Defaults to the first port in var.ports."
  type        = number
  default     = null
}

variable "ingress_tls_enabled" {
  description = "Whether to enable TLS on the Ingress (cert-manager issues the certificate)"
  type        = bool
  default     = true
}

variable "ingress_cert_issuer" {
  description = "cert-manager ClusterIssuer name. Lab provides 'selfsigned' out of the box."
  type        = string
  default     = "selfsigned"
}

variable "ingress_annotations" {
  description = "Extra annotations for the Ingress resource"
  type        = map(string)
  default     = {}
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_enabled" {
  description = "Whether to create a PVC and mount it into the container"
  type        = bool
  default     = false
}

variable "storage_type" {
  description = <<-EOT
    Which StorageClass to use for the PVC:
      longhorn       — replicated, node-portable (default StorageClass, recommended)
      synology-iscsi — NAS-provisioned LUN per PVC, node-portable
      local-storage  — node-pinned, no failover (use only when node affinity is required)
  EOT
  type    = string
  default = "longhorn"

  validation {
    condition     = contains(["longhorn", "synology-iscsi", "local-storage"], var.storage_type)
    error_message = "storage_type must be longhorn, synology-iscsi, or local-storage."
  }
}

variable "storage_size" {
  description = "PVC storage request (e.g. 1Gi, 10Gi, 50Gi)"
  type        = string
  default     = "1Gi"
}

variable "storage_mount_path" {
  description = "Absolute path inside the container where the PVC is mounted"
  type        = string
  default     = "/data"
}

variable "storage_access_modes" {
  description = "PVC access modes"
  type        = list(string)
  default     = ["ReadWriteOnce"]
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "monitoring_enabled" {
  description = "Whether to create a ServiceMonitor for Prometheus scraping"
  type        = bool
  default     = false
}

variable "monitoring_port" {
  description = "Named port on the Service that exposes Prometheus metrics"
  type        = string
  default     = "metrics"
}

variable "monitoring_path" {
  description = "HTTP path where metrics are exposed"
  type        = string
  default     = "/metrics"
}

variable "prometheus_release" {
  description = "Helm release name of kube-prometheus-stack (determines ServiceMonitor discovery label)"
  type        = string
  default     = "kube-prometheus-stack"
}

# ── Scheduling ────────────────────────────────────────────────────────────────

variable "update_strategy" {
  description = "Deployment update strategy: RollingUpdate or Recreate"
  type        = string
  default     = "RollingUpdate"
}

variable "service_account_name" {
  description = "Existing ServiceAccount to run pods under. null = namespace default."
  type        = string
  default     = null
}
