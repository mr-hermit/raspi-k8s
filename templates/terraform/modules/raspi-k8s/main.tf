locals {
  namespace = var.create_namespace ? module.namespace[0].name : var.namespace

  # Selector labels derived from the app name — used by both Deployment and Service
  selector_labels = { "app" = var.app_name }

  # Build the service port list from the combined var.ports definition
  service_ports = [for p in var.ports : {
    name        = p.name
    port        = coalesce(p.service_port, p.container_port)
    target_port = p.container_port
    node_port   = p.node_port
    protocol    = coalesce(p.protocol, "TCP")
  }]

  # Port to which Ingress routes — first service port by default
  ingress_service_port = coalesce(
    var.ingress_service_port,
    length(local.service_ports) > 0 ? local.service_ports[0].port : 80
  )

  # Name of the PVC created by whichever storage submodule is active
  pvc_name = var.storage_enabled ? (
    var.storage_type == "longhorn" ? module.longhorn_pvc[0].name : (
      var.storage_type == "synology-iscsi" ? module.synology_pvc[0].name : module.local_pvc[0].name
    )
  ) : null
}

# ── Namespace ─────────────────────────────────────────────────────────────────

module "namespace" {
  count  = var.create_namespace ? 1 : 0
  source = "./modules/namespace"

  name   = var.namespace
  labels = var.namespace_labels
}

# ── Storage ───────────────────────────────────────────────────────────────────

module "longhorn_pvc" {
  count  = var.storage_enabled && var.storage_type == "longhorn" ? 1 : 0
  source = "./modules/longhorn-pvc"

  name         = "${var.app_name}-data"
  namespace    = local.namespace
  size         = var.storage_size
  access_modes = var.storage_access_modes
  labels       = var.labels

  depends_on = [module.namespace]
}

module "synology_pvc" {
  count  = var.storage_enabled && var.storage_type == "synology-iscsi" ? 1 : 0
  source = "./modules/synology-pvc"

  name         = "${var.app_name}-data"
  namespace    = local.namespace
  size         = var.storage_size
  access_modes = var.storage_access_modes
  labels       = var.labels

  depends_on = [module.namespace]
}

module "local_pvc" {
  count  = var.storage_enabled && var.storage_type == "local-storage" ? 1 : 0
  source = "./modules/local-pvc"

  name      = "${var.app_name}-data"
  namespace = local.namespace
  size      = var.storage_size
  labels    = var.labels

  depends_on = [module.namespace]
}

# ── Workload ──────────────────────────────────────────────────────────────────

module "deployment" {
  source = "./modules/deployment"

  name      = var.app_name
  namespace = local.namespace
  labels    = var.labels

  image    = var.image
  replicas = var.replicas
  command  = var.command
  args     = var.args

  ports = [for p in var.ports : {
    name           = p.name
    container_port = p.container_port
    protocol       = coalesce(p.protocol, "TCP")
  }]

  env                 = var.env
  env_from_configmaps = var.env_from_configmaps
  env_from_secrets    = var.env_from_secrets

  resources_requests_cpu    = var.resources_requests_cpu
  resources_requests_memory = var.resources_requests_memory
  resources_limits_memory   = var.resources_limits_memory
  resources_limits_cpu      = var.resources_limits_cpu

  update_strategy      = var.update_strategy
  service_account_name = var.service_account_name

  liveness_probe_http_path  = var.liveness_probe_http_path
  liveness_probe_http_port  = var.liveness_probe_http_port
  readiness_probe_http_path = var.readiness_probe_http_path
  readiness_probe_http_port = var.readiness_probe_http_port

  volumes = var.storage_enabled ? [{
    name            = "data"
    pvc_claim_name  = local.pvc_name
    config_map_name = null
    secret_name     = null
    empty_dir       = false
    host_path       = null
    host_path_type  = null
  }] : []

  volume_mounts = var.storage_enabled ? [{
    name       = "data"
    mount_path = var.storage_mount_path
    sub_path   = null
    read_only  = false
  }] : []

  depends_on = [
    module.namespace,
    module.longhorn_pvc,
    module.synology_pvc,
    module.local_pvc,
  ]
}

# ── Service ───────────────────────────────────────────────────────────────────

module "service" {
  source = "./modules/service"

  name      = var.app_name
  namespace = local.namespace
  labels    = var.labels
  selector  = local.selector_labels
  type      = var.service_type
  ports     = local.service_ports

  depends_on = [module.namespace]
}

# ── Ingress ───────────────────────────────────────────────────────────────────

module "ingress" {
  count  = var.ingress_enabled ? 1 : 0
  source = "./modules/ingress"

  name      = var.app_name
  namespace = local.namespace
  labels    = var.labels

  host            = var.ingress_host
  tls_enabled     = var.ingress_tls_enabled
  tls_secret_name = "${var.app_name}-tls"
  cluster_issuer  = var.ingress_cert_issuer
  annotations     = var.ingress_annotations

  paths = [{
    path         = var.ingress_path
    path_type    = "Prefix"
    service_name = var.app_name
    service_port = local.ingress_service_port
  }]

  depends_on = [module.namespace, module.service]
}

# ── Monitoring ────────────────────────────────────────────────────────────────

module "monitoring" {
  count  = var.monitoring_enabled ? 1 : 0
  source = "./modules/monitoring"

  name      = var.app_name
  namespace = local.namespace
  labels    = var.labels

  service_selector   = local.selector_labels
  prometheus_release = var.prometheus_release

  endpoints = [{
    port     = var.monitoring_port
    path     = var.monitoring_path
    scheme   = "http"
    interval = "30s"
  }]

  depends_on = [module.namespace, module.service]
}
