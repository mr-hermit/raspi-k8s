output "sample_app_url" {
  description = "URL to reach sample-app via NodePort on the control-plane node"
  value       = "http://${split(":", var.registry)[0]}:${module.sample_app.node_ports["http"]}"
}
