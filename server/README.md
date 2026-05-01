# Server — OS baseline

Generic Ubuntu Server baseline for every node in the lab. Run this once on
fresh nodes before any component-specific playbook (storage, Kubernetes, etc.).

It is intentionally independent of Kubernetes and storage so it can be reused
for any Ubuntu Server node you add to the lab.

## What it does

| Task | Detail |
|------|--------|
| Package upgrade | `apt upgrade` — reboots if the kernel changed |
| Passwordless sudo | Adds `ansible_user ALL=(ALL) NOPASSWD:ALL` to sudoers |
| SSH key auth | Installs your public key in `authorized_keys` |
| SSH hardening | Drops `/etc/ssh/sshd_config.d/00-lab-hardening.conf` to disable password auth |
| `/etc/hosts` | Adds every cluster peer so nodes resolve each other by hostname |

## Usage

All commands run from the **project root** (`raspi/`) on your control machine:

```bash
ansible-playbook -i inventory.ini server/server-setup.yaml
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | Public key installed on every node |

Override on the command line:
```bash
ansible-playbook -i inventory.ini server/server-setup.yaml \
  -e "ssh_public_key_path=~/.ssh/id_rsa.pub"
```

## Notes

- **Reboot** only happens when `apt upgrade` actually installs a new kernel.
  On a fresh Ubuntu Server image this almost always triggers.
- **SSH hardening** writes a numbered drop-in (`00-lab-hardening.conf`) that
  is loaded before Ubuntu's cloud-init drop-in (`50-cloud-init.conf`), so the
  `PasswordAuthentication no` setting wins even if cloud-init resets it.
- **`/etc/hosts`** entries use the node's OS hostname (`ansible_hostname` fact),
  which is what Kubernetes uses when registering nodes — not the Ansible
  inventory alias. Make sure each Pi's hostname matches its `ansible_host`
  value in `inventory.ini`.
