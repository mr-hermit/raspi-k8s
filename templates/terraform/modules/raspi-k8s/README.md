# raspi-k8s Module

Composable Terraform module for deploying workloads into the Raspberry Pi lab
Kubernetes cluster.

Recommended audience:
- Developers who want a convenient and safe default for deploying test apps
  into a near-real Kubernetes environment.

## What This Module Creates

- Deployment
- Service
- Optional Ingress (with optional cert-manager TLS)
- Optional PVC with selectable storage backend:
  - longhorn
  - synology-iscsi
  - local-storage
- Optional ServiceMonitor for Prometheus
- Optional namespace creation

## Why It Contains a Nested modules Directory

This is a standard Terraform composition pattern.

- `raspi-k8s` is an umbrella module.
- Child modules under `./modules/*` encapsulate specific resources.
- Umbrella module exposes a simplified interface for most consumers.

## Interface Stability

Stability tiers:
- Tier 1 (recommended): `raspi-k8s` root inputs/outputs.
- Tier 2 (advanced/direct use): child modules under `./modules/*`.

Tier 2 modules are intended to be reusable, but may evolve faster than Tier 1
as the umbrella module matures.

## Compatibility

- Terraform: `>= 1.3.0`
- Provider: `hashicorp/kubernetes >= 2.20.0`

## Typical Usage

Use this module from your deployment repository:

```hcl
module "my_app" {
  source = "../templates/terraform/modules/raspi-k8s"

  app_name  = "my-app"
  namespace = "default"
  image     = "nginx:1.27-alpine"

  ports = [
    {
      name           = "http"
      container_port = 80
      service_port   = 80
    }
  ]
}
```

For complete examples, see:
- `../../examples/simple-web-app`
- `../../examples/postgres-synology`
