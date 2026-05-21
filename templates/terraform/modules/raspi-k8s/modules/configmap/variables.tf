variable "name" {
  description = "ConfigMap name"
  type        = string
}

variable "namespace" {
  description = "Namespace to create the ConfigMap in"
  type        = string
}

variable "data" {
  description = "Plain-text key-value pairs stored in the ConfigMap"
  type        = map(string)
  default     = {}
}

variable "binary_data" {
  description = "Base64-encoded binary data stored in the ConfigMap"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to the ConfigMap"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to the ConfigMap"
  type        = map(string)
  default     = {}
}
