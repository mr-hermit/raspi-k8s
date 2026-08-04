# Logging — Loki + Promtail

Deploys centralized log aggregation for the cluster:

- **Loki** — single-binary mode, filesystem storage on a `synology-iscsi` PVC
- **Promtail** — DaemonSet on every node (including the control plane), ships logs
  from **every pod in every namespace** to Loki

This replaces `kubectl logs` as the only way to see pod output — logs now survive pod
restarts and are queryable from Grafana with history.

This is pure infrastructure: no per-project dashboards, alerts, or scrape filtering.
Ingestion is cluster-wide by design — scope down at query time in Grafana
(`{namespace="myproject"}` in LogQL), not by restricting what Promtail ships. Individual
projects add their own Grafana log views on top of this in their own repos.

## Prerequisites

- `addons/monitoring/monitoring-setup.yaml` completed — reuses its `monitoring` namespace
  and Grafana instance (the datasource ConfigMap is picked up by Grafana's built-in
  sidecar, so no separate Grafana deploy happens here)
- `addons/synology-csi/synology-csi-setup.yaml` completed — Loki's PVC uses the
  `synology-iscsi` StorageClass

## Usage

```bash
ansible-playbook -i inventory.ini addons/logging/logging-setup.yaml
```

## Accessing logs

Open Grafana at `http://<any-node-ip>:32000` (same instance as the Prometheus
dashboards), go to **Explore**, pick the **Loki** datasource, and query with LogQL:

```logql
{namespace="default"}
{namespace="registry", app="registry"} |= "error"
```

## Selective execution

| Tag | What it runs |
|-----|--------------|
| `logging_prereqs` | Add/update the `grafana` Helm repo |
| `loki`            | Install Loki (single binary, filesystem storage, synology-iscsi PVC) |
| `promtail`        | Install Promtail DaemonSet — ships logs from all namespaces, all nodes |
| `datasource`      | Apply the ConfigMap that registers Loki as a Grafana datasource |

## Variables

Defined in `inventory.ini`:

| Variable | Default | Description |
|---|---|---|
| `loki_pvc_size` | `200Gi` | Loki filesystem storage PVC size — sized generously, ~2TB free on the NAS |
| `loki_retention_days` | `30` | How long Loki keeps logs before the compactor deletes them |

## Notes

- **Namespace** — Loki and Promtail install into the existing `monitoring` namespace
  rather than a dedicated one. Grafana's datasource sidecar (deployed by
  kube-prometheus-stack) only watches ConfigMaps in its own namespace by default, so
  sharing the namespace is what makes auto-provisioning work without extra sidecar
  configuration.
- **Retention** — raising `loki_retention_days` later just means re-running with
  `--tags loki` after updating `inventory.ini`; shrinking it triggers the compactor to
  delete older chunks on its next cycle, it doesn't reclaim PVC space immediately.
- **Not HA** — single Loki replica, `replication_factor: 1`. Matches the lab's scale;
  if the pod restarts there's a brief gap in ingestion, but the PVC (and its data)
  persists across restarts and reschedules on `synology-iscsi`.
- **Control-plane logs included** — Promtail tolerates the control-plane taint so
  system pod logs (kube-apiserver, etcd, Calico, etc.) are captured too, not just
  worker workloads.
