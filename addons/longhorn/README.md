# Longhorn — Distributed Block Storage

Deploys [Longhorn](https://longhorn.io) as the default StorageClass for the K8s cluster.
Longhorn stores volume replicas on the iSCSI mount (`/mnt/storage/longhorn`) on each node,
giving stateful workloads replicated block storage with automatic failover and a management UI.

**Run after `storage/iscsi-setup.yaml` and `k8s/k8s-setup.yaml`.**

---

## Why Longhorn instead of local-storage

The existing `local-storage` StorageClass (OpenEBS local) pins a PVC to the node where the pod
first schedules. If that node goes down, the service is unavailable until it recovers — and the
pod can never move.

Longhorn replicates each volume across two nodes. The pod can run on any node that holds a replica,
so a single node failure does not take the service down.

| | `local-storage` | `longhorn` (default) |
|---|---|---|
| Pod placement | Pinned to one node forever | Any node with a replica |
| Node failure | Service down | Pod reschedules, stays up |
| Replicas > 1 | Pointless (storage not shared) | Supported |
| Snapshots / backups | No | Yes |
| Volume expansion | No | Yes |

---

## Architecture

```
                       K8s cluster
                       ─────────────────────────────────────────────
Pod on rasserv02
    │
    ▼
Longhorn Engine          (thin process, co-located with pod)
    │                         │
    ▼                         ▼
Replica file                Replica file
rasserv01                   rasserv03
/mnt/storage/longhorn/      /mnt/storage/longhorn/
<vol-id>/                   <vol-id>/

Pod sees a regular block device — full POSIX, no NFS caveats.
Replicas live on the iSCSI mount, not the Pi's SD card.
```

---

## Quick start

```bash
# Prepare all nodes + deploy Longhorn in one go
ansible-playbook -i inventory.ini addons/longhorn/longhorn-setup.yaml
```

Stage by stage:

```bash
# 1. Install OS packages, load kernel module, create data directory on each node
ansible-playbook -i inventory.ini addons/longhorn/longhorn-setup.yaml --tags longhorn_prereqs

# 2. Install Longhorn via Helm and wait for readiness
ansible-playbook -i inventory.ini addons/longhorn/longhorn-setup.yaml --tags longhorn_deploy
```

---

## Accessing the Longhorn UI

Longhorn UI is exposed as a NodePort on every cluster node:

```
http://<any-node-ip>:30700
```

The UI shows live volume health, replica placement, node disk usage, snapshots, and backup status.

---

## Using Longhorn PVCs

Longhorn is the default StorageClass. A PVC without an explicit `storageClassName` uses it:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  # storageClassName omitted — Longhorn is used automatically
```

To reference it explicitly:

```yaml
  storageClassName: longhorn
```

### In the Terraform module

```hcl
module "my_service" {
  source    = "<path>/modules/raspi-k8s"
  app_name  = "my-service"
  image     = "raspi/my-service:1.0.0"

  volumes = [{
    name           = "data"
    storage_class  = "longhorn"   # or omit — longhorn is the default
    storage_size   = "5Gi"
    mount_path     = "/data"
  }]
}
```

---

## Variables

Defined in `inventory.ini`:

| Variable | Default | Description |
|---|---|---|
| `longhorn_data_path` | `/mnt/storage/longhorn` | Directory on each node where replica files are stored |
| `longhorn_replica_count` | `2` | Number of replicas per volume |
| `longhorn_ui_nodeport` | `30700` | NodePort for the Longhorn web UI |

---

## Tags

| Tag | What it does |
|---|---|
| `longhorn_prereqs` | Install `open-iscsi`, `nfs-common`, `util-linux`; load `iscsi_tcp` module; add multipath blacklist; create data directory — runs on all nodes |
| `longhorn_deploy` | Add Helm repo, install Longhorn, wait for DaemonSet and UI deployment to roll out — runs on control plane |

---

## Notes

- **Replica count 2** — chosen to keep overhead low on a 3-node Pi cluster while tolerating one
  node failure. Increase to 3 in `inventory.ini` for full redundancy (higher CPU/RAM cost).
- **Data path must be on iSCSI** — Longhorn replica files must live under `/mnt/storage/`.
  Never point `longhorn_data_path` at a path on the Pi's SD card.
- **multipath blacklist** — the playbook writes `/etc/multipath.conf` to prevent `multipathd`
  from claiming Longhorn block devices. Safe to apply even if `multipath-tools` is not installed.
- **`local-storage` coexists** — both StorageClasses remain available. The registry and other
  node-pinned workloads continue using `local-storage` explicitly.
- **RWX volumes** — Longhorn supports `ReadWriteMany` access mode internally via NFS, which is
  why `nfs-common` is installed on every node as a prerequisite.
