# KEDA Addon

This playbook deploys [KEDA](https://keda.sh/) (Kubernetes Event-driven Autoscaling) to your Kubernetes cluster using the official manifest.

## Usage

Run the playbook from the `addons/keda` directory:

```sh
ansible-playbook -i ../../inventory.ini keda-setup.yaml
```

## Customization
- You can change the KEDA version by editing the `keda_version` variable in the playbook.
- The playbook creates a dedicated namespace (`keda`) for KEDA components.

## References
- [KEDA Documentation](https://keda.sh/docs/)
- [KEDA GitHub](https://github.com/kedacore/keda)
