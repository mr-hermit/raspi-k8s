provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

module "web_app" {
  source = "../../modules/raspi-k8s"

  app_name         = var.app_name
  namespace        = var.namespace
  create_namespace = true

  image    = var.image
  replicas = 2

  ports = [
    {
      name           = "http"
      container_port = 80
      service_port   = 80
    }
  ]

  service_type = "ClusterIP"

  ingress_enabled     = true
  ingress_host        = var.ingress_host
  ingress_path        = "/"
  ingress_tls_enabled = true
  ingress_cert_issuer = "selfsigned"

  liveness_probe_http_path  = "/"
  liveness_probe_http_port  = 80
  readiness_probe_http_path = "/"
  readiness_probe_http_port = 80

  resources_requests_cpu    = "50m"
  resources_requests_memory = "64Mi"
  resources_limits_cpu      = "250m"
  resources_limits_memory   = "128Mi"

  labels = {
    "app.kubernetes.io/component"  = "frontend"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}
