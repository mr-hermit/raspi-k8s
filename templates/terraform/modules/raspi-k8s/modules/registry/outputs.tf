output "registry_url" {
  description = "Registry base URL — pass to Docker daemon insecure-registries config"
  value       = local.registry_url
}

output "image_ref" {
  description = "Full image reference ready for use in Kubernetes manifests (host:port/name:tag)"
  value       = local.image_ref
}

output "image_name" {
  description = "Image name without registry or tag"
  value       = var.image_name
}

output "tag" {
  description = "Image tag"
  value       = var.tag
}
