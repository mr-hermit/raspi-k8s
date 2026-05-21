variable "name" {
  description = "PersistentVolumeClaim name"
  type        = string
}

variable "namespace" {
  description = "Namespace for the PVC"
  type        = string
}

variable "size" {
  description = "Storage request size (e.g. 5Gi, 20Gi)"
  type        = string
}

variable "access_modes" {
  description = "Access modes for the PVC — Longhorn supports ReadWriteOnce and ReadWriteMany"
  type        = list(string)
  default     = ["ReadWriteOnce"]
}

variable "storage_class_name" {
  description = "StorageClass to use — override when using a custom Longhorn class (e.g. with different replica count)"
  type        = string
  default     = "longhorn"
}

variable "replicas" {
  description = "Number of Longhorn volume replicas. null = use the StorageClass default (2)"
  type        = number
  default     = null
}

variable "wait_until_bound" {
  description = "Whether Terraform should wait for the PVC to be bound before continuing"
  type        = bool
  default     = false
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
