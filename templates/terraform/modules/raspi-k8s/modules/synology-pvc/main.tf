# Creates a PVC backed by the Synology CSI driver (csi.san.synology.com).
# The driver provisions one iSCSI LUN per PVC on the NAS via the DSM API.
# Pods using this PVC can reschedule freely across nodes.
resource "kubernetes_persistent_volume_claim_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
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
