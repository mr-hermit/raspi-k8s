variable "app_name" {
  description = "Application name — used for K8s resource names, labels, and DNS"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Create the namespace if it does not already exist"
  type        = bool
  default     = false
}

variable "image" {
  description = "Full container image reference, e.g. rasserv01:30500/myapp:1.0.0"
  type        = string
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "ports" {
  description = "Ports exposed by the container and mapped on the Service"
  type = list(object({
    name           = string
    container_port = number
    service_port   = number
    node_port      = optional(number) # only used when service_type = NodePort
  }))
}

variable "service_type" {
  description = "Kubernetes Service type"
  type        = string
  default     = "NodePort"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be ClusterIP, NodePort, or LoadBalancer."
  }
}

variable "env" {
  description = "Environment variables injected into the container"
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "CPU and memory requests/limits"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "node_selector" {
  description = "Node selector labels to constrain pod scheduling"
  type        = map(string)
  default     = {}
}

variable "volumes" {
  description = <<-EOT
    Persistent volumes backed by hostPath directories on the iSCSI-mounted
    volume (/mnt/storage). Each entry creates a PV, PVC, and mounts the path
    inside the container.
  EOT
  type = list(object({
    name        = string
    mount_path  = string
    host_path   = string            # absolute path on the node, e.g. /mnt/storage/myapp/data
    size        = optional(string, "10Gi")
    access_mode = optional(string, "ReadWriteOnce")
  }))
  default = []
}
