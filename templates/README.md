# Templates

Reusable building blocks for deploying workloads to the lab cluster.
Copy what you need into your own deployment repository and adapt from there.

## Contents

| Path | Purpose |
|------|---------|
| `LAB-CONTEXT.md.template` | Template for generating the AI/assistant context file |
| `scripts/build-push.sh` | Build a multi-platform ARM64 image and push it to the lab registry |
| `terraform/modules/raspi-k8s/` | Umbrella Terraform module — Deployment + Service + optional PVC/Ingress |
| `terraform/examples/simple-web-app/` | Nginx + Ingress example (no persistence) |
| `terraform/examples/postgres-synology/` | PostgreSQL with `synology-iscsi` PVC |

## Generating LAB-CONTEXT.md

`LAB-CONTEXT.md` is a local, git-ignored snapshot that gives AI/code assistants
context about your specific cluster (node IPs, addons, storage classes, ports).
It is generated from `inventory.ini` and the live cluster state.

```bash
# Run from the project root
python scripts/generate-lab-context.py
```

Optional flags:

```bash
python scripts/generate-lab-context.py \
  --inventory inventory.ini \
  --template templates/LAB-CONTEXT.md.template \
  --output LAB-CONTEXT.md \
  --kubeconfig ~/.kube/config-raspi
```

The script detects which addons are deployed by querying `kubectl get namespaces`
and includes only the relevant sections. If `kubectl` is unavailable or the cluster
is unreachable, addon sections are omitted with a warning.

## Terraform modules

See [terraform/README.md](terraform/README.md) for module reference and usage.
