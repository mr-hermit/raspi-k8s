variable "name" {
  description = "Deployment name — also used as the container name and app label value"
  type        = string
}

variable "namespace" {
  description = "Namespace for the Deployment"
  type        = string
}

variable "labels" {
  description = "Additional labels applied to the Deployment and pod template"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations applied to the Deployment metadata"
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Annotations applied to the pod template (e.g. to trigger rolling restarts on config changes)"
  type        = map(string)
  default     = {}
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

# ── Container ────────────────────────────────────────────────────────────────

variable "image" {
  description = "Container image reference (e.g. rasserv01:30500/myapp:1.0.0 or raspi/myapp:1.0.0)"
  type        = string
}

variable "image_pull_policy" {
  description = "Image pull policy: Always, IfNotPresent, or Never"
  type        = string
  default     = "IfNotPresent"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be Always, IfNotPresent, or Never."
  }
}

variable "command" {
  description = "Override the container entrypoint (ENTRYPOINT)"
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Override the container command arguments (CMD)"
  type        = list(string)
  default     = []
}

# ── Ports ─────────────────────────────────────────────────────────────────────

variable "ports" {
  description = "Container ports to declare (informational; does not affect networking)"
  type = list(object({
    name           = string
    container_port = number
    protocol       = optional(string, "TCP")
  }))
  default = []
}

# ── Environment ───────────────────────────────────────────────────────────────

variable "env" {
  description = "Plain key-value environment variables injected into the container"
  type        = map(string)
  default     = {}
}

variable "env_from_field_ref" {
  description = "Env vars sourced from the Downward API (e.g. metadata.namespace, status.podIP)"
  type = list(object({
    name       = string
    field_path = string
  }))
  default = []
}

variable "env_from_configmaps" {
  description = "Names of ConfigMaps whose keys are injected as env vars (envFrom)"
  type        = list(string)
  default     = []
}

variable "env_from_secrets" {
  description = "Names of Secrets whose keys are injected as env vars (envFrom)"
  type        = list(string)
  default     = []
}

# ── Resources ─────────────────────────────────────────────────────────────────

variable "resources_requests_cpu" {
  description = "CPU request — keep low on Raspberry Pi (e.g. 50m, 100m)"
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
  description = "CPU limit (null = no limit, recommended on Pi to allow burst)"
  type        = string
  default     = null
}

# ── Volumes ───────────────────────────────────────────────────────────────────

variable "volumes" {
  description = "Volumes to attach to the pod. Exactly one of pvc_claim_name, config_map_name, secret_name, empty_dir, or host_path should be set per entry."
  type = list(object({
    name            = string
    pvc_claim_name  = optional(string, null)
    config_map_name = optional(string, null)
    secret_name     = optional(string, null)
    empty_dir       = optional(bool, false)
    host_path       = optional(string, null)
    host_path_type  = optional(string, null)
  }))
  default = []
}

variable "volume_mounts" {
  description = "Volume mounts for the main container"
  type = list(object({
    name       = string
    mount_path = string
    sub_path   = optional(string, null)
    read_only  = optional(bool, false)
  }))
  default = []
}

# ── Health checks ─────────────────────────────────────────────────────────────

variable "liveness_probe_http_path" {
  description = "HTTP path for liveness probe (e.g. /healthz). Null disables HTTP liveness check."
  type        = string
  default     = null
}

variable "liveness_probe_http_port" {
  description = "Port for HTTP liveness probe"
  type        = number
  default     = null
}

variable "liveness_probe_exec" {
  description = "Command for exec liveness probe (alternative to HTTP). Null disables exec liveness check."
  type        = list(string)
  default     = null
}

variable "liveness_probe_initial_delay" {
  description = "Seconds before liveness probe starts"
  type        = number
  default     = 30
}

variable "liveness_probe_period" {
  description = "Seconds between liveness probe attempts"
  type        = number
  default     = 10
}

variable "liveness_probe_failure_threshold" {
  description = "Consecutive failures before the container is restarted"
  type        = number
  default     = 3
}

variable "readiness_probe_http_path" {
  description = "HTTP path for readiness probe. Null disables HTTP readiness check."
  type        = string
  default     = null
}

variable "readiness_probe_http_port" {
  description = "Port for HTTP readiness probe"
  type        = number
  default     = null
}

variable "readiness_probe_exec" {
  description = "Command for exec readiness probe. Null disables exec readiness check."
  type        = list(string)
  default     = null
}

variable "readiness_probe_initial_delay" {
  description = "Seconds before readiness probe starts"
  type        = number
  default     = 10
}

variable "readiness_probe_period" {
  description = "Seconds between readiness probe attempts"
  type        = number
  default     = 10
}

variable "readiness_probe_failure_threshold" {
  description = "Consecutive failures before the pod is removed from Service endpoints"
  type        = number
  default     = 3
}

# ── Scheduling ────────────────────────────────────────────────────────────────

variable "node_selector" {
  description = "Node labels to constrain scheduling (empty = no constraint, all Pi nodes qualify)"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for tainted nodes"
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, null)
    effect   = optional(string, null)
  }))
  default = []
}

# ── Security ──────────────────────────────────────────────────────────────────

variable "pod_security_context" {
  description = "Pod-level security context. null = use Kubernetes defaults."
  type = object({
    run_as_user     = optional(number, null)
    run_as_group    = optional(number, null)
    fs_group        = optional(number, null)
    run_as_non_root = optional(bool, null)
  })
  default = null
}

variable "container_security_context" {
  description = "Container-level security context. null = use Kubernetes defaults."
  type = object({
    read_only_root_filesystem  = optional(bool, false)
    allow_privilege_escalation = optional(bool, null)
    run_as_user                = optional(number, null)
  })
  default = null
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

variable "update_strategy" {
  description = "Deployment update strategy: RollingUpdate or Recreate"
  type        = string
  default     = "RollingUpdate"

  validation {
    condition     = contains(["RollingUpdate", "Recreate"], var.update_strategy)
    error_message = "update_strategy must be RollingUpdate or Recreate."
  }
}

variable "termination_grace_period_seconds" {
  description = "Seconds Kubernetes waits for the pod to shut down before SIGKILL"
  type        = number
  default     = 30
}

variable "service_account_name" {
  description = "ServiceAccount to run the pod under. null = use the namespace default."
  type        = string
  default     = null
}
