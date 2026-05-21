# No Kubernetes resources — this module is a pure helper that constructs
# image reference strings for the lab's private registry.
locals {
  registry_url = "${var.registry_host}:${var.registry_port}"
  image_ref    = "${local.registry_url}/${var.image_name}:${var.tag}"
}
