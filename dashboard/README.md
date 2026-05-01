# Dashboard — Headlamp

Lightweight Kubernetes web UI. Chosen over the official K8s Dashboard because it runs
as a single container (~60MB RAM vs Dashboard's ~200MB across multiple pods), leaving
more headroom for actual workloads on Pi hardware.

## Prerequisites

`k8s/k8s-setup.yaml` completed.

## Usage

```bash
# Install Headlamp (NodePort access)
ansible-playbook -i inventory.ini dashboard/dashboard-setup.yaml

# Also expose via Ingress (run ingress/ingress-setup.yaml first)
ansible-playbook -i inventory.ini dashboard/dashboard-setup.yaml --tags headlamp_ingress
```

## Access

**NodePort** (always available):
```
http://<any-node-ip>:30100
```

**Ingress** (after `headlamp_ingress` tag + Ingress Controller installed):
```
https://headlamp.local:30443
```
Add `<any-node-ip> headlamp.local` to your local `/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`.

## Authentication

Headlamp uses your kubeconfig or a service account token. On first open, paste a token
generated from the control plane:

```bash
kubectl create token headlamp -n headlamp
```

## Selective execution

| Tag | What it runs |
|-----|--------------|
| `headlamp`         | Install Headlamp (NodePort) |
| `headlamp_ingress` | Apply Ingress resource for `headlamp.local` |
