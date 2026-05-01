# Kubernetes Cluster Setup

Ansible playbook to provision a Kubernetes 1.32 cluster on Raspberry Pi 5 nodes
using CRI-O as the container runtime and Calico as the CNI.

**Prerequisite:** run `server/server-setup.yaml` first (OS baseline, SSH, `/etc/hosts`).

**Storage** (`storage/iscsi-setup.yaml`) is optional — the playbook works regardless
of whether iSCSI volumes are mounted. If storage was set up, K8s data directories
are bind-mounted from the NAS; otherwise they live on the SD card.

## Layout

```
k8s/
├── k8s-setup.yaml      Main playbook — all cluster setup in one file, separated by tags
└── files/              Static files copied to nodes during setup
    ├── crio/           CRI-O runtime configuration
    ├── cni/            CNI bridge configuration files
    └── services/       Kubernetes manifests (Grafana service, storage class)
```

## Usage

Run the full playbook (recommended):
```bash
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml
```

Or run individual stages — useful for re-running a specific step:

| Tag | Description |
|-----|-------------|
| `k8s_setup` | Kernel modules, sysctl, apt repos, kubelet, CRI-O, Helm binary, CNI plugins |
| `k8s_storage` | K8s dirs + bind mounts (auto-detects iSCSI) |
| `k8s_cluster_init` | `kubeadm init`, kubeconfig, Calico CNI |
| `k8s_workers_join` | Generate join token, join workers, label nodes |
| `k8s_workers_label` | Re-label worker nodes only |

```bash
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --tags k8s_setup
```

### Useful flags

```bash
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --check   # dry run
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --limit worker_node_1
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml -v
```

## After provisioning

**bash / WSL / macOS:**
```bash
scp hermit@<control-plane-ip>:~/.kube/config ~/.kube/config-raspi
export KUBECONFIG=~/.kube/config-raspi
kubectl get nodes -o wide
kubectl top nodes
```

**PowerShell (Windows):**
```powershell
scp hermit@<control-plane-ip>:~/.kube/config "$env:USERPROFILE\.kube\config-raspi"
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-raspi"
kubectl get nodes -o wide
kubectl top nodes
```

To make `KUBECONFIG` permanent in PowerShell (survives session restart):
```powershell
[System.Environment]::SetEnvironmentVariable("KUBECONFIG", "$env:USERPROFILE\.kube\config-raspi", "User")
```

## Known limitations

- **`k8s_workers_join`** generates a new bootstrap token each run. If workers are
  already joined, `kubeadm join` will fail — this is harmless. Only run this tag
  against fresh nodes or after `kubeadm reset` on the worker.
- **CNI plugins** and **Helm** are downloaded as prebuilt ARM64 binaries from GitHub — no Go toolchain needed.
- **Calico tigera-operator** must be applied with `--server-side --force-conflicts` due to a CRD annotation size limit in standard `kubectl apply`.
