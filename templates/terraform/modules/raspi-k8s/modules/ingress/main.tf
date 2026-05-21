locals {
  tls_secret_name = coalesce(var.tls_secret_name, "${var.name}-tls")

  cert_annotations = var.tls_enabled ? {
    "cert-manager.io/cluster-issuer" = var.cluster_issuer
  } : {}
}

resource "kubernetes_ingress_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = merge(local.cert_annotations, var.annotations)
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.host

      http {
        dynamic "path" {
          for_each = var.paths
          content {
            path      = path.value.path
            path_type = path.value.path_type

            backend {
              service {
                name = path.value.service_name
                port {
                  number = path.value.service_port
                }
              }
            }
          }
        }
      }
    }

    dynamic "tls" {
      for_each = var.tls_enabled ? [1] : []
      content {
        hosts       = [var.host]
        secret_name = local.tls_secret_name
      }
    }
  }
}
