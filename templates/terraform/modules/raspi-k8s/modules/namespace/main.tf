resource "kubernetes_namespace_v1" "this" {
  metadata {
    name        = var.name
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
  }
}
