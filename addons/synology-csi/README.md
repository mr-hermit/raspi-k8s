# Synology CSI Driver

Deploys the [Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi) so
Kubernetes can provision iSCSI LUNs directly on the Synology NAS via the DSM API.

When a PVC is created using the `synology-iscsi` StorageClass, the CSI controller calls DSM and
creates a new dedicated LUN on the NAS for that PVC. The LUN is attached to the pod's node over
iSCSI and presented as a block device — no manual NAS configuration needed per volume.

**Run after `k8s/k8s-setup.yaml`.**
This addon is independent of `storage/iscsi-setup.yaml` — it creates its own LUNs and does not
use the per-node mounts at `/mnt/storage`.

---

## Prerequisites

- Synology DSM 7+ with **SAN Manager** package installed
- A DSM user account in the **administrators** group, or with explicit access to both
  **DSM** and **Storage Manager** (DSM → Control Panel → User & Group → Edit → Application Privileges)
- `nas_dsm_username` and `nas_dsm_password` set in `inventory.ini`

### Verify DSM credentials before running

```bash
curl -s "http://192.168.50.189:5000/webapi/auth.cgi?api=SYNO.API.Auth&method=login&version=3&account=<user>&passwd=<pass>&session=test&format=sid"
```

`"success":true` with a `sid` means credentials and connectivity are good.
`"error":{"code":402}` means the account lacks API access — check Application Privileges in DSM.

---

## How it works

```
kubectl apply PVC
      │
      ▼
Synology CSI Controller  (StatefulSet, 1 replica)
      │  calls DSM API
      ▼
Synology NAS (DSM)
      │  creates iSCSI LUN under nas_volume_path
      ▼
Synology CSI Node plugin  (DaemonSet, one pod per worker node)
      │  logs in via iscsiadm, attaches LUN to the pod's node
      ▼
Pod sees a regular block device — ext4, full POSIX, no NFS caveats
```

The pod is not pinned to a node — if it reschedules, the node plugin on the new node
re-attaches the same LUN transparently.

---

## Quick start

```bash
# Prepare nodes + deploy driver in one go
ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml
```

Stage by stage:

```bash
# 1. Install open-iscsi on all nodes
ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml --tags csi_prereqs

# 2. Deploy the CSI driver and StorageClass
ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml --tags csi_deploy
```

Update DSM credentials without redeploying the full driver:

```bash
ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml --tags csi_secret
```

### Verify after install

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: synology-iscsi
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-pvc -w   # should go Pending → Bound within ~5s
kubectl delete pvc test-pvc   # LUN is deleted from NAS automatically
```

---

## Using the StorageClass

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: synology-iscsi
  resources:
    requests:
      storage: 10Gi
```

When the PVC is deleted, the LUN is deleted from the NAS automatically (`reclaimPolicy: Delete`).

### In the Terraform module

```hcl
module "my_service" {
  source   = "<path>/modules/raspi-k8s"
  app_name = "my-service"
  image    = "raspi/my-service:1.0.0"

  volumes = [{
    name          = "data"
    storage_class = "synology-iscsi"
    storage_size  = "10Gi"
    mount_path    = "/data"
  }]
}
```

---

## Variables

Defined in `inventory.ini`:

| Variable | Default | Description |
|---|---|---|
| `synology_csi_version` | `v1.1.3` | Release tag to install |
| `nas_host` | `192.168.50.189` | NAS IP — shared with iSCSI setup |
| `nas_dsm_port` | `5000` | DSM web UI port (5000 HTTP / 5001 HTTPS) |
| `nas_dsm_https` | `false` | Use HTTPS for DSM API calls |
| `nas_dsm_username` | — | DSM user with admin or Storage Manager access |
| `nas_dsm_password` | — | Password for the DSM user |
| `nas_volume_path` | `/volume1` | Storage pool root on the NAS — see note below |
| `synology_csi_default_class` | `false` | Set `true` to make `synology-iscsi` the default StorageClass |

---

## Tags

| Tag | What it does |
|---|---|
| `csi_prereqs` | Install `open-iscsi` and start `iscsid` on all nodes |
| `csi_deploy` | Create namespace, apply driver manifests, wait for readiness, apply StorageClass |
| `csi_secret` | (Re)create the `client-info-secret` K8s secret — run alone after changing DSM credentials |
| `csi_storageclass` | Apply the `synology-iscsi` StorageClass only — required after changing `nas_volume_path` |

---

## Notes

- **`nas_volume_path` must be the storage pool root** — set it to `/volume1` (or `/volume2` etc.),
  not a subdirectory like `/volume1/iscsi`. The CSI driver passes this directly to DSM as the LUN
  location; DSM rejects any path that isn't a storage pool root with `Unable to find location`.
  After changing this value, the StorageClass must be deleted and recreated:
  ```bash
  kubectl delete storageclass synology-iscsi
  ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml --tags csi_storageclass
  ```
- **DSM user permissions** — the account needs to be in the `administrators` group, or have
  explicit access to both DSM and Storage Manager under Application Privileges. A 402 error from
  the DSM API login means insufficient permissions, not wrong credentials.
- **NAS as single point of failure** — unlike Longhorn, data lives on the NAS. If the NAS goes
  offline, pods using Synology-backed PVCs will stall. This matches the rest of the lab since the
  per-node iSCSI mounts have the same dependency.
- **Pod mobility** — unlike `local-storage`, a pod using a Synology PVC can reschedule to any
  node. The CSI node plugin on the new node re-attaches the LUN transparently.
- **Coexists with other StorageClasses** — `local-storage`, `longhorn`, and `synology-iscsi` can
  all be present simultaneously. Reference the desired class by name in each PVC.
