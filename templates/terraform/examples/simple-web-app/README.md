# Simple Web App Example

This example deploys only a web application (nginx) with Ingress and TLS.
No database and no persistent volume are created.

This folder is a reusable template. Copy it into your own deployment repository
and adapt variables/images there.

## Prerequisites

- Kubernetes cluster is reachable from your control machine.
- Ingress and cert-manager addons are installed.

## Usage

```bash
cd templates/terraform/examples/simple-web-app
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Notes

- For local name resolution of ingress_host, add a hosts entry pointing to any
  node IP that serves ingress traffic.
