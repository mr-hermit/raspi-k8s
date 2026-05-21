output "service_monitor_name" {
  description = "ServiceMonitor resource name"
  value       = var.name
}

output "prometheus_rule_name" {
  description = "PrometheusRule resource name (null when no alert_rules are defined)"
  value       = length(var.alert_rules) > 0 ? var.name : null
}

output "namespace" {
  description = "Namespace where monitoring resources were created"
  value       = var.namespace
}
