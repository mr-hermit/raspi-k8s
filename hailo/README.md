# Hailo — AI HAT+ (Hailo-8, 26 TOPS)

Configures Ubuntu Server to drive a Hailo AI HAT+ installed over the Raspberry
Pi 5's PCIe FPC connector: kernel driver (DKMS), firmware, and the HailoRT
runtime (`hailortcli`, `libhailort`).

**Run this after `server/server-setup.yaml`.** Independent of storage and
Kubernetes — it only touches the node(s) listed in the `[hailo_nodes]`
inventory group.

---

## Why this needs its own playbook

Ubuntu Server doesn't ship Hailo support. Raspberry Pi publishes the
`hailo*` packages (driver, firmware, runtime) through their own apt
repository, built against Raspberry Pi OS (Debian bookworm). This playbook:

1. Adds that repository with an apt **pin file** that blocks every other
   package on it — only `hailofw`, `hailort`, `hailo-dkms`, and (optionally)
   `hailo-tappas-core` / `python3-hailort` are ever allowed to install from
   bookworm. Nothing else on the node can be pulled from that origin.
2. Installs matching kernel headers and lets DKMS build the `hailo_pci`
   module against the running Ubuntu kernel — Hailo's driver is the same
   either way, only the kernel headers it's built against differ.
3. Reboots so the driver attaches to the device, then verifies
   `/dev/hailo0` exists and `hailortcli` can talk to the chip.

## Prerequisites

- `server/server-setup.yaml` completed.
- AI HAT+ physically seated and the node power-cycled (not just rebooted)
  at least once after attaching it — the HAT's EEPROM is read at cold boot.
- The node is listed in `[hailo_nodes]` in `inventory.ini`:
  ```ini
  [hailo_nodes]
  worker_node_2   # rasserv03
  ```

## Usage

```bash
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml
```

Stage by stage:
```bash
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_repo
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_packages
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_reboot
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_verify
```

## Optional components

Both default to `false` to keep the install minimal — override with `-e` or
in `inventory.ini`:

| Variable | Adds | Why it's off by default |
|----------|------|--------------------------|
| `hailo_install_tappas` | `hailo-tappas-core` (GStreamer pipelines) | Pulls a heavy chain of gstreamer/opencv deps you don't need for plain `.hef` inference |
| `hailo_install_python_bindings` | `python3-hailort` | Hard-pins `python3 (>= 3.11, << 3.12)`; Ubuntu 24.04+ ships 3.12 by default, so this will fail to install unless Python 3.11 is also available (e.g. via the `deadsnakes` PPA) |

## Verifying manually

```bash
ssh hermit@rasserv03
ls /dev/hailo0
hailortcli fw-control identify
```

Expected `identify` output includes the board name, chip type (`HAILO8`),
and firmware version.

## Troubleshooting

**`/dev/hailo0` missing after reboot**
- `dmesg | grep -i hailo` — look for PCIe enumeration and driver load errors
- `lspci | grep -i hailo` — if the device doesn't show up at all, reseat the
  HAT and power-cycle (unplug, not just reboot) the Pi
- `dkms status` — confirm `hailo-dkms` built and installed for the running
  kernel; if it shows "added" but not "installed", the kernel headers
  package didn't match — rerun with `--tags hailo_packages`

**apt fails to resolve `hailofw`/`hailort`/`hailo-dkms`**
- The Raspberry Pi repo only tracks one suite (`bookworm` by default, see
  `hailo_apt_suite`). If Raspberry Pi has moved their stable suite to a
  newer codename, update `hailo_apt_suite` in `inventory.ini`.

**Driver loads but inference is slow (~50% of expected FPS)**
- PCIe may have negotiated Gen2 instead of Gen3. Check with:
  ```bash
  sudo lspci -vv -s $(lspci | grep -i hailo | cut -d' ' -f1) | grep LnkSta
  ```
- The AI HAT+ (unlike the M.2-based AI Kit) auto-negotiates Gen3 and
  normally doesn't need `dtparam=pciex1_gen=3` in
  `/boot/firmware/config.txt` — only add it if `LnkSta` shows Gen2.
