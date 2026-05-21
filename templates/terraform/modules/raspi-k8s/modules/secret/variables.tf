variable "name" {
  description = "Secret name"
  type        = string
}

variable "namespace" {
  description = "Namespace to create the Secret in"
  type        = string
}

variable "type" {
  description = "Kubernetes Secret type (e.g. Opaque, kubernetes.io/tls, kubernetes.io/dockerconfigjson)"
  type        = string
  default     = "Opaque"
}

variable "string_data" {
  description = "Plain-text key-value pairs; Kubernetes base64-encodes them automatically"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "data" {
  description = "Already base64-encoded key-value pairs"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "labels" {
  description = "Labels to apply to the Secret"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to the Secret"
  type        = map(string)
  default     = {}
}
