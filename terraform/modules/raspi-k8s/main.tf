locals {
  labels = { app = var.app_name }

  # Resolve namespace: use the created one if create_namespace=true, otherwise
  # trust the caller-supplied string (namespace must already exist).
  namespace = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : var.namespace

  volumes_map = { for v in var.volumes : v.name => v }
}

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# ── Persistent storage ────────────────────────────────────────────────────────
# One PV + PVC pair per volume entry. PVs use hostPath so they are backed by
# the iSCSI volume already mounted on the node at /mnt/storage.
# Pin the pod with node_selector to the node that owns the data.

resource "kubernetes_persistent_volume_v1" "this" {
  for_each = local.volumes_map

  metadata {
    name = "${var.app_name}-${each.key}"
  }

  spec {
    capacity                         = { storage = each.value.size }
    access_modes                     = [each.value.access_mode]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""

    # Pre-bind directly to this app's PVC so the PV is not claimed by anything else.
    claim_ref {
      namespace = local.namespace
      name      = "${var.app_name}-${each.key}"
    }

    persistent_volume_source {
      host_path {
        path = each.value.host_path
        type = "DirectoryOrCreate"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "this" {
  for_each = local.volumes_map

  metadata {
    name      = "${var.app_name}-${each.key}"
    namespace = local.namespace
  }

  spec {
    access_modes       = [each.value.access_mode]
    storage_class_name = ""

    resources {
      requests = { storage = each.value.size }
    }

    volume_name = kubernetes_persistent_volume_v1.this[each.key].metadata[0].name
  }
}

# ── Deployment ────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.app_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        node_selector = var.node_selector

        container {
          name  = var.app_name
          image = var.image

          dynamic "port" {
            for_each = var.ports
            content {
              name           = port.value.name
              container_port = port.value.container_port
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }

          dynamic "volume_mount" {
            for_each = local.volumes_map
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value.mount_path
            }
          }
        }

        dynamic "volume" {
          for_each = local.volumes_map
          content {
            name = volume.key
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim_v1.this[volume.key].metadata[0].name
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.this]
}

# ── Service ───────────────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.app_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type     = var.service_type
    selector = local.labels

    dynamic "port" {
      for_each = var.ports
      content {
        name        = port.value.name
        port        = port.value.service_port
        target_port = port.value.container_port
        # node_port must be omitted entirely for ClusterIP; Kubernetes rejects
        # an explicit null value, so we conditionally set it.
        node_port = var.service_type == "NodePort" ? port.value.node_port : null
      }
    }
  }
}
