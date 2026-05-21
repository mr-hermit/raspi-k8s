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
  description = "Namespace where postgres is deployed"
  type        = string
  default     = "database"
}

variable "app_name" {
  description = "Name of the postgres deployment and service"
  type        = string
  default     = "postgres"
}

variable "image" {
  description = "Postgres container image"
  type        = string
  default     = "postgres:16-alpine"
}

variable "postgres_db" {
  description = "Database created by postgres on first start"
  type        = string
  default     = "appdb"
}

variable "postgres_user" {
  description = "Database user created by postgres on first start"
  type        = string
  default     = "appuser"
}

variable "postgres_password" {
  description = "Password for postgres_user"
  type        = string
  sensitive   = true
}

variable "postgres_storage_size" {
  description = "PVC size for postgres data on Synology iSCSI"
  type        = string
  default     = "20Gi"
}
