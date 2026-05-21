# raspi-k8s Child Modules

Child modules used by the `raspi-k8s` umbrella module.

These modules can be used directly by advanced consumers, but the preferred
entrypoint for most teams is the parent module at `../`.

## Child Modules

- `namespace`
- `deployment`
- `service`
- `ingress`
- `monitoring`
- `local-pvc`
- `longhorn-pvc`
- `synology-pvc`
- `configmap`
- `secret`
- `rbac`
- `tls-cert`
- `registry`

## Stability Notes

- Direct consumption is supported for flexibility.
- Expect faster interface evolution here than in the umbrella module.
- Prefer pinning module versions/tags when consumed directly from shared repos.
