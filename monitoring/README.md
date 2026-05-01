# Monitoring — Metrics Server + Prometheus + Grafana

Deploys the cluster monitoring stack:

- **Metrics Server** — lightweight in-cluster metrics aggregator; enables `kubectl top` and Horizontal Pod Autoscaler
- **kube-prometheus-stack** — Prometheus, Alertmanager, and Grafana via Helm

This is optional. Skip it if you don't need cluster metrics or dashboards.

## Prerequisites

- `k8s/k8s-setup.yaml` completed — cluster must be up and `kubectl` working
- Helm installed on the cluster nodes (included in `k8s_setup`)

## Usage

```bash
ansible-playbook -i inventory.ini monitoring/monitoring-setup.yaml
```

## Accessing Grafana

Grafana is exposed as a NodePort on port **32000** on every cluster node:

```
http://<any-node-ip>:32000
```

Default credentials: `admin` / `prom-operator`

## Selective execution

| Tag | What it runs |
|-----|--------------|
| `metrics_server` | Metrics Server — powers `kubectl top` and HPA |
| `prometheus`     | kube-prometheus-stack — cluster metrics collection |
| `grafana`        | Grafana NodePort service — dashboard UI |
| `loki`           | Loki + Promtail — log aggregation across all nodes |
