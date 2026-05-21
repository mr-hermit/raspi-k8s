variable "name" {
  description = "Service name"
  type        = string
}

variable "namespace" {
  description = "Namespace for the Service"
  type        = string
}

variable "selector" {
  description = "Label selector that matches the pods this Service targets"
  type        = map(string)
}

variable "type" {
  description = "Service type: ClusterIP, NodePort, LoadBalancer, or None (headless)"
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer", "ExternalName"], var.type)
    error_message = "type must be ClusterIP, NodePort, LoadBalancer, or ExternalName."
  }
}

variable "ports" {
  description = "List of port definitions for the Service"
  type = list(object({
    name        = string
    port        = number
    target_port = optional(number, null) # defaults to port when null
    node_port   = optional(number, null) # required when type = NodePort; pick from 30000-32767
    protocol    = optional(string, "TCP")
  }))
}

variable "cluster_ip" {
  description = "Set to \"None\" to create a headless Service (used with StatefulSets)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to the Service"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to the Service"
  type        = map(string)
  default     = {}
}
