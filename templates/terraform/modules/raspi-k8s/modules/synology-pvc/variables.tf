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
  description = "Access modes for the PVC"
  type        = list(string)
  default     = ["ReadWriteOnce"]
}

variable "storage_class_name" {
  description = "StorageClass to use — override only when you have a custom Synology class"
  type        = string
  default     = "synology-iscsi"
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
