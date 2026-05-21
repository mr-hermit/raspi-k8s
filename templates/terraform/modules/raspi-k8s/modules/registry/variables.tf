variable "registry_host" {
  description = "Hostname or IP of the private registry (default: lab control-plane node)"
  type        = string
  default     = "rasserv01"
}

variable "registry_port" {
  description = "NodePort on which the registry is exposed"
  type        = number
  default     = 30500
}

variable "image_name" {
  description = "Image name without registry prefix or tag (e.g. myapp)"
  type        = string
}

variable "tag" {
  description = "Image tag"
  type        = string
  default     = "latest"
}
