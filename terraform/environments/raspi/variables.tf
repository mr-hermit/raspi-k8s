variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the raspi cluster"
  type        = string
  default     = "~/.kube/config-raspi"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use. Leave empty to use the file's current-context."
  type        = string
  default     = ""
}

variable "registry" {
  description = "Hostname and port of the private container registry"
  type        = string
  default     = "rasserv01:30500"
}
