# Registry — Private Container Registry

A private Docker-compatible registry deployed on the K8s cluster, storing
images on the iSCSI volume already provided by the Synology NAS.

**Run after `k8s/k8s-setup.yaml`.**

---

## Architecture

```
                      K8s cluster
                      ──────────────────────────────────────────
Your machine ──push──▶ rasserv01:30500  (NodePort)
                              │
                        registry:2 pod   (control plane node)
                              │
                        /mnt/storage/registry   (iSCSI volume)
                              │
                      rasserv01/02/03 ──pull──▶ rasserv01:30500
```

The registry pod is pinned to the control plane node where the iSCSI volume
is already mounted. All nodes are configured to trust the registry over plain
HTTP (no TLS), which is appropriate for an isolated lab network.

---

## Quick start

```bash
# Configure all nodes + deploy registry in one go
ansible-playbook -i inventory.ini addons/registry/registry-setup.yaml
```

Stage by stage:
```bash
# 1. Configure CRI-O on all nodes to trust the insecure registry
ansible-playbook -i inventory.ini addons/registry/registry-setup.yaml --tags registry_config

# 2. Deploy registry Deployment + Service to K8s
ansible-playbook -i inventory.ini addons/registry/registry-setup.yaml --tags registry_deploy
```

---

## Using the registry

### Push from your local machine

Configure Docker to allow the insecure registry (add to `/etc/docker/daemon.json`
on your workstation, then restart Docker):

```json
{
  "insecure-registries": ["rasserv01:30500"]
}
```

Build for ARM64 (Raspberry Pi 5 architecture) and push in one step:

```bash
docker buildx build --platform linux/arm64 -t rasserv01:30500/myimage:latest --push .
```

If you are already on an ARM64 machine (Apple Silicon, another Pi):

```bash
docker build -t rasserv01:30500/myimage:latest .
docker push rasserv01:30500/myimage:latest
```

### Pull in K8s manifests

Use either the full address or the `raspi/` short-name prefix:

```yaml
# Full address
image: rasserv01:30500/myimage:latest

# Short name (CRI-O resolves raspi/* → rasserv01:30500/*)
image: raspi/myimage:latest
```

No `imagePullSecrets` needed — CRI-O is already configured to trust the registry
and knows the `raspi/` prefix maps to it.

### Verify the registry is working

```bash
# List repositories
curl http://rasserv01:30500/v2/_catalog

# List tags for an image
curl http://rasserv01:30500/v2/myimage/tags/list
```

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `registry_nodeport` | `30500` | NodePort exposed on every cluster node |
| `registry_storage_size` | `50Gi` | Storage allocated for image data |
| `registry_storage_path` | `/mnt/storage/registry` | Path on iSCSI volume |
| `registry_namespace` | `registry` | K8s namespace for the registry workload |

Override on the command line:
```bash
ansible-playbook -i inventory.ini addons/registry/registry-setup.yaml \
  -e "registry_nodeport=30501 registry_storage_size=100Gi"
```

---

## Tags

| Tag | What it does |
|-----|-------------|
| `registry_config` | Add insecure-registry + `raspi/` prefix alias to CRI-O on all nodes, restart CRI-O |
| `registry_deploy` | Create PV/PVC, deploy registry Deployment + NodePort Service |

---

## Notes

- **No TLS** — only suitable for a private, trusted lab network. To add TLS,
  mount a certificate into the container and set `REGISTRY_HTTP_TLS_*` env vars.
- **Single-node storage** — images are stored on the control plane's iSCSI volume.
  Each node has its own LUN, so the registry pod must stay on the control plane
  (enforced by `nodeSelector`).
- **No authentication** — the registry accepts pushes from anyone on the network.
  Set `REGISTRY_AUTH_*` env vars to enable htpasswd authentication if needed.
