provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

resource "kubernetes_namespace_v1" "database" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/part-of" = "raspi-lab"
      "managed-by"                = "terraform"
    }
  }
}

resource "kubernetes_secret_v1" "postgres_env" {
  metadata {
    name      = "postgres-env"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    POSTGRES_DB       = var.postgres_db
    POSTGRES_USER     = var.postgres_user
    POSTGRES_PASSWORD = var.postgres_password
  }

  depends_on = [kubernetes_namespace_v1.database]
}

module "postgres" {
  source = "../../modules/raspi-k8s"

  app_name         = var.app_name
  namespace        = var.namespace
  create_namespace = false

  image    = var.image
  replicas = 1

  ports = [
    {
      name           = "postgres"
      container_port = 5432
      service_port   = 5432
    }
  ]

  service_type = "ClusterIP"

  env_from_secrets = [kubernetes_secret_v1.postgres_env.metadata[0].name]

  storage_enabled    = true
  storage_type       = "synology-iscsi"
  storage_size       = var.postgres_storage_size
  storage_mount_path = "/var/lib/postgresql/data"

  resources_requests_cpu    = "100m"
  resources_requests_memory = "256Mi"
  resources_limits_cpu      = "500m"
  resources_limits_memory   = "512Mi"

  update_strategy = "Recreate"

  labels = {
    "app.kubernetes.io/component"  = "database"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  depends_on = [
    kubernetes_namespace_v1.database,
    kubernetes_secret_v1.postgres_env,
  ]
}
