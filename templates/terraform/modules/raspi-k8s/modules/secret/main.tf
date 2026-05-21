resource "kubernetes_secret_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
  }

  type = var.type
  data = merge(
    length(var.data) > 0 ? var.data : {},
    { for k, v in var.string_data : k => base64encode(v) }
  )
}
