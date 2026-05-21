# Requires kube-prometheus-stack CRDs (ServiceMonitor, PrometheusRule) to be
# installed before `terraform plan`. The lab monitoring addon installs them.
# The 'release' label must match the Helm release name of kube-prometheus-stack
# so that Prometheus picks up the ServiceMonitor.
locals {
  base_labels = merge(
    { "managed-by" = "terraform", "release" = var.prometheus_release },
    var.labels
  )
}

resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.base_labels
    }
    spec = {
      selector = {
        matchLabels = var.service_selector
      }
      endpoints = [for ep in var.endpoints : {
        port     = ep.port
        path     = ep.path
        scheme   = ep.scheme
        interval = ep.interval
      }]
    }
  }
}

resource "kubernetes_manifest" "prometheus_rule" {
  count = length(var.alert_rules) > 0 ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.base_labels
    }
    spec = {
      groups = [{
        name = var.name
        rules = [for rule in var.alert_rules : {
          alert = rule.alert
          expr  = rule.expr
          for   = rule.for_duration
          labels = {
            severity = rule.severity
          }
          annotations = {
            summary     = rule.summary
            description = rule.description
          }
        }]
      }]
    }
  }
}
