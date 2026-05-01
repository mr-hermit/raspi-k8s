# Storage — iSCSI block volumes from Synology NAS

Provides each Raspberry Pi with a dedicated block device over iSCSI, replacing
the SD card for all Kubernetes heavy-write directories.

**Run this playbook before `k8s/k8s-setup.yaml`.**

---

## Why iSCSI over NFS

| | NFS | iSCSI |
|---|---|---|
| Protocol level | File (NFS daemon) | Block (TCP socket) |
| Latency | 1–5 ms (protocol overhead + RPC) | 0.1–0.5 ms (direct block I/O) |
| Kubernetes suitability | Problematic for etcd fsync | Suitable for all K8s workloads |
| Kubernetes node stability | Can cause node NotReady on NAS hiccup | Reconnects transparently |
| Filesystem | Managed by NAS | Managed by Pi (ext4) |

etcd performs a synchronous fsync on every commit. Over NFS this can easily
exceed etcd's 1-second election timeout, causing leader elections and node
drops. iSCSI behaves like a local disk — latency stays below the threshold.

---

## Architecture

```
Each Raspberry Pi                    Synology NAS
──────────────────────               ──────────────────────────────
/boot          (SD card)             iSCSI Target: raspi-rasserv01
/              (SD card)               └── LUN 1 (64 GB thin)
                                              │
/mnt/storage ←── iSCSI (TCP/GbE) ────────────┘
  ├── etcd/          bind → /var/lib/etcd      (control plane)
  ├── crio/          bind → /var/lib/crio
  ├── kubelet/       bind → /var/lib/kubelet
  ├── log-pods/      bind → /var/log/pods
  └── log-containers/ bind → /var/log/containers
```

Boot ordering enforced by systemd:

```
network-online.target
  └── open-iscsi.service     (reconnects iSCSI sessions)
        └── mnt-storage.mount (ext4 on iSCSI LUN)
              ├── bind mounts  (var-lib-etcd.mount, etc.)
              └──   ├── crio.service    (Requires=mnt-storage.mount)
                    └── kubelet.service (Requires=mnt-storage.mount)
```

If the NAS is unreachable, `nofail` lets the Pi boot, but kubelet and CRI-O
will not start — intentional, to avoid running K8s without its data.

---

## Part 1 — Manual preparation on Synology NAS

### 1.1 Install SAN Manager

DSM → **Package Center** → search **SAN Manager** → Install.

### 1.2 Create one iSCSI Target per Pi

1. Open **SAN Manager** → **iSCSI** → **Target** → **Add**
2. Fill in the form:
   - **Target name** (alias): use the Pi hostname — e.g. `raspi-rasserv01`
     > The playbook discovers targets by matching `ansible_host` against the
     > target IQN. The auto-generated IQN will contain whatever name you give.
   - **IQN**: leave on *Auto* (Synology generates `iqn.2000-01.com.synology:…`)
   - **CHAP authentication**: optional; if enabled, add credentials to inventory
3. Click **Next** → **Finish**
4. Repeat for `raspi-rasserv02` and `raspi-rasserv03`

After creating, note the auto-generated IQN for each target — you will see it
in SAN Manager → Target list. Example:
```
iqn.2000-01.com.synology:diskstation.raspi-rasserv01.a1b2c3d4
```

### 1.3 Create one LUN per Pi and map it to the target

1. **SAN Manager** → **LUN** → **Add**
2. Settings:
   - **Name**: `lun-rasserv01`
   - **Location**: your main storage pool
   - **Capacity**: 64 GB (adjust — must hold etcd, container images, kubelet state)
   - **Type**: Thin Provisioned (saves NAS space; use Thick for maximum performance)
3. On the **Map** step → select the matching target (`raspi-rasserv01`)
4. **Finish**
5. Repeat for rasserv02 and rasserv03

### 1.4 Configure NAS network for iSCSI

Synology uses port **3260/TCP** for iSCSI. Ensure:
- NAS and Pi nodes are on the same network segment (or routed with low latency)
- Your switch/firewall allows port 3260 between Pi IPs and NAS IP
- For best performance, put iSCSI traffic on a dedicated VLAN or at least
  ensure the NAS Gigabit port isn't saturated

### 1.5 Verify from a Pi (optional)

```bash
# Install client and test discovery before running the playbook
sudo apt install -y open-iscsi
sudo iscsiadm -m discovery -t sendtargets -p diskstation:3260
# Expected output (one line per target):
# 192.168.1.100:3260,1 iqn.2000-01.com.synology:diskstation.raspi-rasserv01.xxx
# 192.168.1.100:3260,1 iqn.2000-01.com.synology:diskstation.raspi-rasserv02.xxx
# 192.168.1.100:3260,1 iqn.2000-01.com.synology:diskstation.raspi-rasserv03.xxx
```

---

## Part 2 — Configure inventory

Edit `inventory.ini` at the project root. The iSCSI variables are already
present; adjust them to match your environment:

```ini
nas_host=diskstation        # or use IP: 192.168.1.100
nas_iscsi_port=3260
iscsi_mount_point=/mnt/storage
iscsi_initiator_prefix=iqn.2024-01.lab.raspi
```

To encrypt the credentials:
```bash
ansible-vault encrypt inventory.ini
# Run playbooks with: --ask-vault-pass
```

---

## Part 3 — Run the playbook

All commands are run from the **project root** (`raspi/`):

```bash
# Full run (recommended for fresh setup):
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml

# Stage by stage:
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags iscsi_client
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags iscsi_connect
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags iscsi_mount
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags iscsi_dirs
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags iscsi_bind
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --tags systemd_override

# Single node (useful for troubleshooting):
ansible-playbook -i inventory.ini storage/iscsi-setup.yaml --limit worker_node_1
```

### Available tags

| Tag | What it does |
|-----|-------------|
| `iscsi_client` | Install `open-iscsi`, set initiator IQN, configure iscsid |
| `iscsi_connect` | Discover target, login, format LUN (first run only) |
| `iscsi_mount` | Add to `/etc/fstab` via UUID, mount at `/mnt/storage` |
| `iscsi_dirs` | Create K8s subdirectory layout on the mounted volume |
| `iscsi_bind` | Bind-mount K8s paths onto iSCSI subdirs |
| `systemd_override` | Drop-ins: kubelet/CRI-O `Requires=mnt-storage.mount` |

---

## Part 4 — Proceed with Kubernetes setup

Once this playbook completes on all nodes, run the K8s setup:

```bash
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --tags basic_setup
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --tags k8s_setup
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --tags k8s_cluster_init
ansible-playbook -i inventory.ini k8s/k8s-setup.yaml --tags k8s_workers_join
```

---

## Verification

```bash
# Check iSCSI session is active
sudo iscsiadm -m session

# Check the volume is mounted
mount | grep storage
df -h /mnt/storage

# Check all bind mounts are in place
mount | grep bind
ls -la /var/lib/etcd /var/lib/crio /var/lib/kubelet

# Check systemd ordering is configured
systemctl cat kubelet | grep -E "After|Requires"
systemctl cat crio    | grep -E "After|Requires"
```

---

## Troubleshooting

**Discovery returns no targets matching this node**
- Ensure the Synology target alias/name contains `ansible_host` (e.g. `raspi-rasserv01`)
- Or hardcode the IQN: add `iscsi_target_iqn=iqn.2000-01.com.synology:...` as a
  host variable in `inventory.ini`

**Device doesn't appear after login**
- Check `dmesg | grep -i scsi` on the Pi
- Verify the LUN is mapped to the target in SAN Manager
- Try `sudo iscsiadm -m node -T <iqn> --login` manually

**mkfs refuses to run (device busy)**
- The device may already be formatted and mounted; the playbook will skip mkfs if `blkid` detects a filesystem
- If you need to reformat: `sudo umount /mnt/storage && sudo mkfs.ext4 -L k8s-rasserv0X /dev/sdX`

**kubelet/CRI-O fail to start after reboot**
- Run `systemctl status mnt-storage.mount` — the iSCSI session must be established first
- Run `systemctl status open-iscsi` — must be active before the mount
- Check NAS reachability: `ping diskstation`
