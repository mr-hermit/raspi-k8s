variable "kubeconfig_path" {
  description = "Absolute path to kubeconfig on your control machine"
  type        = string
}

variable "kubeconfig_context" {
  description = "Optional kubeconfig context name. Leave empty to use current context."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace where the web app is deployed"
  type        = string
  default     = "web"
}

variable "app_name" {
  description = "Name of the web deployment and service"
  type        = string
  default     = "web-app"
}

variable "image" {
  description = "Container image for the web app"
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "ingress_host" {
  description = "Ingress host for the web app"
  type        = string
  default     = "web.raspi.local"
}
