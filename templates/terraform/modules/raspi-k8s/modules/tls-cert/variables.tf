variable "name" {
  description = "cert-manager Certificate resource name"
  type        = string
}

variable "namespace" {
  description = "Namespace to create the Certificate in"
  type        = string
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret that will store the issued certificate and key"
  type        = string
}

variable "common_name" {
  description = "Certificate common name (CN). Defaults to the first entry in dns_names when null."
  type        = string
  default     = null
}

variable "dns_names" {
  description = "DNS SANs to include in the certificate"
  type        = list(string)
  default     = []
}

variable "issuer_ref_name" {
  description = "Name of the cert-manager Issuer or ClusterIssuer. Lab provides 'selfsigned' (ClusterIssuer)."
  type        = string
  default     = "selfsigned"
}

variable "issuer_ref_kind" {
  description = "Kind of the issuer reference: Issuer (namespace-scoped) or ClusterIssuer (cluster-wide)"
  type        = string
  default     = "ClusterIssuer"

  validation {
    condition     = contains(["Issuer", "ClusterIssuer"], var.issuer_ref_kind)
    error_message = "issuer_ref_kind must be Issuer or ClusterIssuer."
  }
}

variable "duration" {
  description = "Requested certificate validity duration (e.g. 2160h = 90 days, 8760h = 1 year)"
  type        = string
  default     = "2160h"
}

variable "renew_before" {
  description = "How long before expiry cert-manager should renew the certificate"
  type        = string
  default     = "360h"
}

variable "labels" {
  description = "Labels to apply to the Certificate resource"
  type        = map(string)
  default     = {}
}
