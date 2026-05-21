locals {
  role_name     = coalesce(var.role_name, var.service_account_name)
  common_labels = merge({ "managed-by" = "terraform" }, var.labels)
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name        = var.service_account_name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  automount_service_account_token = var.automount_token
}

# ── Namespace-scoped Role ─────────────────────────────────────────────────────

resource "kubernetes_role_v1" "this" {
  count = var.create_role && !var.cluster_scoped ? 1 : 0

  metadata {
    name      = local.role_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  dynamic "rule" {
    for_each = var.rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = rule.value.verbs
    }
  }
}

resource "kubernetes_role_binding_v1" "this" {
  count = var.create_role && !var.cluster_scoped ? 1 : 0

  metadata {
    name      = "${local.role_name}-binding"
    namespace = var.namespace
    labels    = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.this[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.this.metadata[0].name
    namespace = var.namespace
  }
}

# ── Cluster-scoped Role ───────────────────────────────────────────────────────

resource "kubernetes_cluster_role_v1" "this" {
  count = var.create_role && var.cluster_scoped ? 1 : 0

  metadata {
    name   = local.role_name
    labels = local.common_labels
  }

  dynamic "rule" {
    for_each = var.rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = rule.value.verbs
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "this" {
  count = var.create_role && var.cluster_scoped ? 1 : 0

  metadata {
    name   = "${local.role_name}-binding"
    labels = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.this[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.this.metadata[0].name
    namespace = var.namespace
  }
}
