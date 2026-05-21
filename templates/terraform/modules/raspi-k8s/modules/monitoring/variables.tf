variable "name" {
  description = "Base name for ServiceMonitor and PrometheusRule resources"
  type        = string
}

variable "namespace" {
  description = "Namespace to create monitoring resources in"
  type        = string
}

variable "service_selector" {
  description = "Label selector that matches the Service to scrape"
  type        = map(string)
}

variable "endpoints" {
  description = "List of scrape endpoint configurations"
  type = list(object({
    port     = string           # named port on the Service (e.g. \"metrics\" or \"http\")
    path     = optional(string, "/metrics")
    scheme   = optional(string, "http")
    interval = optional(string, "30s")
  }))
  default = [{
    port     = "metrics"
    path     = "/metrics"
    scheme   = "http"
    interval = "30s"
  }]
}

variable "prometheus_release" {
  description = "Value for the 'release' label on monitoring resources. Must match the kube-prometheus-stack Helm release name so Prometheus discovers them."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "alert_rules" {
  description = "Alerting rules to create as a PrometheusRule. Leave empty to skip PrometheusRule creation."
  type = list(object({
    alert        = string
    expr         = string
    for_duration = optional(string, "5m")
    severity     = optional(string, "warning")
    summary      = optional(string, "")
    description  = optional(string, "")
  }))
  default = []
}

variable "labels" {
  description = "Additional labels applied to monitoring resources"
  type        = map(string)
  default     = {}
}
