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

1. Removes the stray, unsigned `/etc/apt/sources.list.d/raspi.list` that
   Ubuntu's official Raspberry Pi image preconfigures for the same origin
   (`archive.raspberrypi.com`) — it references a `ui` component that no
   longer exists upstream, and once this playbook adds its own signed
   `raspberrypi.list` for the same origin, apt starts warning about
   duplicate Packages/Translations targets on every run.
2. Adds that repository with an apt **pin file** that blocks every other
   package on it — only `hailofw`, `hailort`, `hailo-dkms`, and (optionally)
   `hailo-tappas-core` / `python3-hailort` are ever allowed to install from
   bookworm. Nothing else on the node can be pulled from that origin.
3. Installs matching kernel headers and runs `dkms autoinstall` so the
   `hailo_pci` module is built and installed for the running kernel — this
   runs on every play, not just first install, so a kernel point-release
   from a later `apt upgrade` (which leaves `dkms status` stuck on "added")
   gets caught and rebuilt automatically on the next run.
4. Drops a udev rule (`/etc/udev/rules.d/51-hailo-videodev.rules`) so the
   device node actually appears. On Ubuntu, unlike Raspberry Pi OS, nothing
   does this automatically — the driver registers its class in sysfs fine,
   but without a rule `/dev/hailo0` never gets created.
5. Registers `hailo_pci` in `/etc/modules-load.d/hailo.conf` so it loads on
   every future boot, not just the one immediately after this playbook runs.
6. Reboots so the driver attaches to the device, then verifies
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
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_udev
ansible-playbook -i inventory.ini hailo/hailo-setup.yaml --tags hailo_boot
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
  package didn't match a later kernel upgrade — rerun with
  `--tags hailo_packages` (runs `dkms autoinstall` to rebuild)
- `ls /sys/class | grep -i hailo` — if this shows a class (e.g.
  `hailo_chardev`) but `/dev/hailo0` still doesn't exist, the udev rule is
  missing or stale — rerun with `--tags hailo_udev` and check
  `/etc/udev/rules.d/51-hailo-videodev.rules`
- `cat /etc/modules-load.d/hailo.conf` — if missing, the module only loaded
  because of the one-time post-install reboot and won't survive the next
  one — rerun with `--tags hailo_boot`

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
