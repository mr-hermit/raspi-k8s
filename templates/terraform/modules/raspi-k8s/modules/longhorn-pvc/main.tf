# Creates a PVC backed by Longhorn distributed block storage.
# Longhorn replicates data across nodes (default: 2 replicas) and supports
# pod rescheduling to any healthy node. Data lives at /mnt/storage/longhorn
# on the iSCSI-mounted volume, not on SD cards.
resource "kubernetes_persistent_volume_claim_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = merge(
      var.annotations,
      var.replicas != null ? {
        "storage.longhorn.io/number-of-replicas" = tostring(var.replicas)
      } : {}
    )
  }

  spec {
    access_modes       = var.access_modes
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.size
      }
    }
  }

  wait_until_bound = var.wait_until_bound
}
