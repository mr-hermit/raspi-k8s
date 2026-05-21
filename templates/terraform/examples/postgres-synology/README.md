# Postgres With Synology PVC Example

This example deploys only PostgreSQL with persistent data on Synology CSI
storage class synology-iscsi.

This folder is a reusable template. Copy it into your own deployment repository
and adapt variables/secrets there.

## Prerequisites

- Kubernetes cluster is reachable from your control machine.
- Synology CSI addon is installed and storage class synology-iscsi exists.

## Usage

```bash
cd templates/terraform/examples/postgres-synology
cp terraform.tfvars.example terraform.tfvars
# set postgres_password before apply
terraform init
terraform plan
terraform apply
```

## Notes

- Postgres uses Recreate strategy to avoid concurrent writers on one data volume.
- PVC is created by raspi-k8s with storage_type set to synology-iscsi.
