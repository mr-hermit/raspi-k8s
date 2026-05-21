# Terraform Templates For Raspberry Pi Lab

This directory is a template/reference library, not a live deployment project.

Primary goal:
- Help developers deploy test workloads to a near-real Kubernetes lab running on Raspberry Pi.

Intended usage:
- Copy selected modules/examples from this directory into your own repository.
- Adjust provider configuration, naming, and secrets in that target repository.
- Run Terraform from that target repository.

Publishing model:
- This template library is designed to be published in a shared GitHub repository.
- The `raspi-k8s` module is the recommended entrypoint for most consumers.

## Structure

- `modules/`
  - Reusable module implementations.
  - Main module: `modules/raspi-k8s`.
- `examples/`
  - Small standalone examples showing module composition.

## Examples

- `examples/simple-web-app`
  - Web app only (nginx), ingress enabled, no database.
- `examples/postgres-synology`
  - PostgreSQL with persistent data on `synology-iscsi` PVC.

## Prerequisites In The Lab

- Kubernetes cluster reachable from your control machine.
- For ingress examples: ingress-nginx + cert-manager installed.
- For Synology storage examples: Synology CSI installed and `synology-iscsi`
  StorageClass available.

## Compatibility Policy

- Terraform: `>= 1.3.0`
- Kubernetes provider: `hashicorp/kubernetes >= 2.20.0`

This baseline is intentionally conservative to maximize compatibility for teams
that are not Terraform experts.

## Notes

- Example `terraform.tfvars.example` files contain placeholders.
- Keep real credentials in environment-specific files outside version control.
