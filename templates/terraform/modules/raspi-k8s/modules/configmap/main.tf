resource "kubernetes_config_map_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
  }

  data        = var.data
  binary_data = length(var.binary_data) > 0 ? var.binary_data : null
}
