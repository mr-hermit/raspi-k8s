variable "name" {
  description = "PersistentVolumeClaim name"
  type        = string
}

variable "namespace" {
  description = "Namespace for the PVC"
  type        = string
}

variable "size" {
  description = "Storage request size (e.g. 10Gi, 50Gi)"
  type        = string
}

variable "storage_class_name" {
  description = "StorageClass to use — override only when using a custom local provisioner class"
  type        = string
  default     = "local-storage"
}

variable "labels" {
  description = "Labels to apply to the PVC"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to the PVC"
  type        = map(string)
  default     = {}
}
