# Raspberry Pi Lab

Ansible playbooks and Terraform modules to turn a cluster of Raspberry Pi 5
nodes and a Synology NAS into a working Kubernetes lab. Each module is
independent and layered — run server setup first, then storage and Kubernetes.

**OS: Ubuntu Server 26.04 LTS for Raspberry Pi 5.**
Flash each node using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) —
select *Other general-purpose OS → Ubuntu → Ubuntu Server 26.04 LTS (64-bit)*.

> **All commands in this project run from your control machine** (laptop, desktop,
> or WSL) — never from one of the Raspberry Pi nodes. Ansible connects to the
> nodes over SSH; Terraform and kubectl use the kubeconfig you copy locally.

## Hardware assumed

| Role | Host | Device |
|------|------|--------|
| Control plane | `rasserv01` | Raspberry Pi 5 |
| Worker | `rasserv02` | Raspberry Pi 5 |
| Worker | `rasserv03` | Raspberry Pi 5 + Hailo AI HAT+ (26 TOPS) |
| NAS | `diskstation` | Synology (any model with SAN Manager) |

## Project layout

```
raspi/
├── ansible.cfg          Ansible configuration (picked up automatically)
├── inventory.ini        All hosts + shared variables
├── scripts/
│   ├── healthcheck.sh          Cluster health check — run from your control machine
│   ├── shutdown.sh             Graceful shutdown — drains workers then powers off all nodes
│   ├── iscsi-troubleshoot.sh   iSCSI post-power-cycle diagnostics and recovery
│   └── generate-lab-context.py Generate LAB-CONTEXT.md from inventory.ini
│
├── test/
│   └── lab-test.sh             Integration tests — provisions PVC, deploys service, tests ingress
│
├── LAB-CONTEXT.md              AI/assistant context snapshot (git-ignored, generated)
│
├── server/              Phase 0 — OS baseline (run first on any fresh node)
│   ├── README.md
│   └── server-setup.yaml → apt upgrade, SSH hardening, sudo, /etc/hosts
│
├── storage/             Phase 1 — iSCSI block storage from Synology NAS (optional)
│   ├── README.md        → Synology manual prep guide + playbook usage
│   └── iscsi-setup.yaml → Attach LUN, format, mount at /mnt/storage
│
├── hailo/               Phase 1 — Hailo AI HAT+ driver/runtime (optional, [hailo_nodes] only)
│   ├── README.md        → Raspberry Pi apt repo + pinning explanation, troubleshooting
│   └── hailo-setup.yaml → DKMS driver, firmware, HailoRT runtime, verification
│
├── k8s/                 Phase 2 — Kubernetes 1.32 cluster (CRI-O + Calico)
│   ├── README.md
│   ├── k8s-setup.yaml   → Full cluster playbook (packages → storage → init → workers → metrics)
│   └── files/           Static config files deployed to nodes
│       ├── crio/
│       ├── cni/
│       └── services/
│
└── addons/              Phases 3-8 — Optional K8s components (install per component)
    ├── monitoring/      Phase 3 — Metrics Server + Prometheus + Grafana + Loki
    │   ├── README.md
    │   ├── monitoring-setup.yaml
    │   └── files/
    │       ├── grafana-service.yaml
    │       └── grafana-ingress.yaml
    │
    ├── ingress/         Phase 4 — Nginx Ingress Controller + cert-manager
    │   ├── README.md
    │   ├── ingress-setup.yaml
    │   └── files/
    │       └── cluster-issuer.yaml
    │
    ├── dashboard/       Phase 5 — Headlamp K8s web UI
    │   ├── README.md
    │   └── dashboard-setup.yaml
    │
    ├── registry/        Phase 6 — Private container registry on K8s
    │   ├── README.md
    │   ├── registry-setup.yaml
    │   └── files/
    │       └── registry.yaml.j2
    │
    ├── longhorn/        Phase 7 — Longhorn distributed block storage (default StorageClass)
    │   ├── README.md
    │   └── longhorn-setup.yaml
    │
    └── synology-csi/    Phase 8 — Synology CSI driver (NAS-provisioned iSCSI LUNs per PVC)
        ├── README.md
        ├── synology-csi-setup.yaml
        └── files/
            ├── client-info.yml.j2
            └── storageclass-iscsi.yaml.j2

templates/               Reusable Terraform modules and helper scripts (copy into your own repo)
├── README.md
├── LAB-CONTEXT.md.template   → Template for generating AI/assistant context
├── scripts/
│   └── build-push.sh         → Build ARM64 image and push to the lab registry
└── terraform/
    ├── modules/
    │   └── raspi-k8s/        → Umbrella module: Deployment + Service + optional PVC/Ingress
    └── examples/
        ├── simple-web-app/   → Nginx + Ingress example
        └── postgres-synology/ → PostgreSQL with synology-iscsi PVC
```

## Before you start

Three things to configure on each Pi **before running any playbook**, ideally
via Raspberry Pi Imager's advanced settings when flashing the SD card:

1. **Hostname** — set to the value you put in `ansible_host` in `inventory.ini`
   (e.g. `rasserv01`). Kubernetes registers nodes by OS hostname; the playbook
   reads this as the `ansible_hostname` fact and writes it into `/etc/hosts`.
   If the hostname and `ansible_host` don't match, worker node labelling will fail.

2. **Static IP** — assign a static IP to each Pi (either via the router's DHCP
   reservation or directly in Ubuntu's netplan). Then update `inventory.ini` to
   use IPs instead of hostnames for `ansible_host`:
   ```ini
   control_plane_node ansible_host=192.168.1.101
   worker_node_1      ansible_host=192.168.1.102
   worker_node_2      ansible_host=192.168.1.103
   ```
   Using IPs avoids any DNS dependency during setup — hostnames alone will fail
   if the router's DNS isn't ready when the playbooks run.

3. **SSH key** — enable SSH and paste your public key during imaging so Ansible
   can connect on the first run without a password prompt.

## Quick start

```bash
# 0. Create your local inventory from the template (inventory.ini is git-ignored)
cp inventory.ini.template inventory.ini
vim inventory.ini    # set ansible_host IPs, nas_host, ansible_user, passwords

# 1. OS baseline — run once on every fresh node
ansible-playbook -i inventory.ini server/server-setup.yaml

# 2. (Optional) Attach iSCSI storage from Synology NAS
#    Manual NAS prep first — see storage/README.md
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml

# 2b. (Optional) Configure a Hailo AI HAT+ — only runs on [hailo_nodes]
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml

# 3. Kubernetes cluster
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml

# Addons — each is independent, run after k8s-setup.yaml
ansible-playbook -i inventory.ini addons/monitoring/monitoring-setup.yaml
ansible-playbook -i inventory.ini addons/ingress/ingress-setup.yaml
ansible-playbook -i inventory.ini addons/dashboard/dashboard-setup.yaml
ansible-playbook -i inventory.ini addons/registry/registry-setup.yaml
ansible-playbook -i inventory.ini addons/longhorn/longhorn-setup.yaml
ansible-playbook -i inventory.ini addons/synology-csi/synology-csi-setup.yaml

# Copy kubeconfig to your control machine
scp hermit@rasserv01:~/.kube/config ~/.kube/config-raspi

# Validate the cluster
./scripts/healthcheck.sh

# Run integration tests (provisions PVC, deploys service, tests ingress)
./test/lab-test.sh

# Generate AI/assistant context file
python scripts/generate-lab-context.py

# Deploy workloads with Terraform — copy templates into your own repo first
# See templates/README.md
```

Each playbook supports tags for running individual stages — useful when re-running
a specific step or skipping parts you don't need. See the README in each directory.

## Requirements

- Terraform ≥ 1.3 on your control machine
- Ansible 2.14+ and Python 3.9+ on your control machine (`pip install ansible`)
- Ubuntu Server 26.04 LTS (64-bit) flashed on each Pi, SSH enabled
- Synology DSM 7+ with SAN Manager package installed (only if using iSCSI storage)

## Securing credentials

`inventory.ini` is git-ignored so it never reaches version control. For an
extra layer of protection, encrypt it with Ansible Vault:

```bash
ansible-vault encrypt inventory.ini
# Run playbooks with --ask-vault-pass
```

## Module READMEs

- [server/README.md](server/README.md) — OS baseline setup
- [storage/README.md](storage/README.md) — Synology iSCSI setup (manual steps + playbook)
- [k8s/README.md](k8s/README.md) — Kubernetes cluster setup
- [addons/monitoring/README.md](addons/monitoring/README.md) — Metrics Server, Prometheus, Grafana, Loki
- [addons/ingress/README.md](addons/ingress/README.md) — Nginx Ingress Controller + cert-manager
- [addons/dashboard/README.md](addons/dashboard/README.md) — Headlamp K8s web UI
- [addons/registry/README.md](addons/registry/README.md) — Private container registry
- [addons/longhorn/README.md](addons/longhorn/README.md) — Longhorn distributed block storage
- [addons/synology-csi/README.md](addons/synology-csi/README.md) — Synology CSI driver (NAS-provisioned LUNs)
- [templates/README.md](templates/README.md) — Terraform templates and build/push script
