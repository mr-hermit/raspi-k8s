# Requires cert-manager CRDs to be installed before `terraform plan`.
# The lab ingress addon installs cert-manager with a pre-configured
# 'selfsigned' ClusterIssuer.
resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = merge({ "managed-by" = "terraform" }, var.labels)
    }
    spec = {
      secretName  = var.secret_name
      commonName  = coalesce(var.common_name, try(var.dns_names[0], var.name))
      dnsNames    = length(var.dns_names) > 0 ? var.dns_names : [coalesce(var.common_name, var.name)]
      duration    = var.duration
      renewBefore = var.renew_before
      issuerRef = {
        name = var.issuer_ref_name
        kind = var.issuer_ref_kind
      }
    }
  }
}
