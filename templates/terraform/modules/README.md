# Terraform Modules (Template Library)

This directory contains reusable Terraform modules for deploying workloads into
the Raspberry Pi lab Kubernetes cluster.

Repository role:
- This repository provides templates and references.
- Modules here are intended to be copied or vendored into another repository
  where actual workload deployments are managed.

Primary module:
- `raspi-k8s`: wraps common K8s resources for app deployment.
  It supports:
  - Deployment + Service
  - Optional Ingress + TLS integration
  - Optional PVC via `longhorn`, `synology-iscsi`, or `local-storage`
  - Optional ServiceMonitor

Module composition note:
- It is normal Terraform practice that `raspi-k8s` contains a nested
  `modules/` directory. The top-level module acts as an umbrella module and
  composes child modules from that folder.

Consumption guidance:
- Preferred for most users: consume only `raspi-k8s`.
- Advanced users may consume child modules directly when they need lower-level
  control, but those child module interfaces can evolve faster than the
  umbrella module interface.

Compatibility baseline:
- Terraform `>= 1.3.0`
- `hashicorp/kubernetes >= 2.20.0`

Related examples live in:
- `../examples/simple-web-app`
- `../examples/postgres-synology`
