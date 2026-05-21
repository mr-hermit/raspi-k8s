variable "name" {
  description = "Ingress resource name"
  type        = string
}

variable "namespace" {
  description = "Namespace for the Ingress"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass to use — lab runs ingress-nginx"
  type        = string
  default     = "nginx"
}

variable "host" {
  description = "Hostname for the Ingress rule (e.g. my-app.local). Must resolve to a node IP via DNS or /etc/hosts."
  type        = string
}

variable "paths" {
  description = "HTTP path routing rules for this host"
  type = list(object({
    path         = optional(string, "/")
    path_type    = optional(string, "Prefix")
    service_name = string
    service_port = number
  }))
  default = []
}

variable "tls_enabled" {
  description = "Whether to enable TLS for this Ingress"
  type        = bool
  default     = false
}

variable "tls_secret_name" {
  description = "Name of the TLS Secret. Defaults to <name>-tls when null. cert-manager will create this secret."
  type        = string
  default     = null
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer to use for TLS certificate issuance. Lab provides 'selfsigned' by default."
  type        = string
  default     = "selfsigned"
}

variable "annotations" {
  description = "Additional annotations to apply to the Ingress"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to the Ingress"
  type        = map(string)
  default     = {}
}
