# Creates a PVC backed by the OpenEBS local provisioner.
# IMPORTANT: local-storage uses WaitForFirstConsumer binding — this PVC will
# remain in Pending state until a pod claims it. Once bound, the pod is
# permanently pinned to the node where it first scheduled (no failover).
# Use only for workloads that tolerate node affinity (e.g. the private registry).
resource "kubernetes_persistent_volume_claim_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = merge({ "managed-by" = "terraform" }, var.labels)
    annotations = var.annotations
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.size
      }
    }
  }

  # WaitForFirstConsumer: Terraform must not block waiting for this PVC to bind.
  wait_until_bound = false
}
