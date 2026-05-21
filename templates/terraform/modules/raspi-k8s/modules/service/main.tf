resource "kubernetes_service_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
  }

  spec {
    selector   = var.selector
    type       = var.type
    cluster_ip = var.cluster_ip

    dynamic "port" {
      for_each = var.ports
      content {
        name        = port.value.name
        port        = port.value.port
        target_port = tostring(port.value.target_port != null ? port.value.target_port : port.value.port)
        node_port   = var.type == "NodePort" ? port.value.node_port : null
        protocol    = coalesce(port.value.protocol, "TCP")
      }
    }
  }
}
