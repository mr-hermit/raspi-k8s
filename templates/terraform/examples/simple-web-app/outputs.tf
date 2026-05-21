output "namespace" {
  description = "Namespace used by this example"
  value       = module.web_app.namespace
}

output "web_service_name" {
  description = "Service name for the web app"
  value       = module.web_app.service_name
}

output "web_ingress_url" {
  description = "HTTPS ingress URL for the web app"
  value       = module.web_app.ingress_https_url
}
