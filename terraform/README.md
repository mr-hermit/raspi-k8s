# Terraform — deploying to the Raspberry Pi K8s lab

Reusable infrastructure-as-code for deploying containerised workloads to the
raspi cluster. Images are pulled from the private registry at `rasserv01:30500`
(set up by `registry/registry-setup.yaml`).

## Layout

```
terraform/
├── modules/
│   └── raspi-k8s/          Reusable deployment module
│       ├── variables.tf    All input variables with defaults and descriptions
│       ├── main.tf         Namespace, PV/PVC (optional), Deployment, Service
│       └── outputs.tf      service_name, node_ports, cluster_ip, …
└── environments/
    └── raspi/              Live environment — one module block per service
        ├── providers.tf    Kubernetes provider pointing at raspi kubeconfig
        ├── variables.tf    kubeconfig_path, registry, …
        ├── main.tf         Module invocations (add your apps here)
        ├── outputs.tf      Service URLs
        └── terraform.tfvars  Actual values (gitignore if they contain secrets)
```

## Prerequisites

- Terraform ≥ 1.6 (`brew install terraform` or from [terraform.io](https://developer.hashicorp.com/terraform/install))
- Kubeconfig for the raspi cluster at `~/.kube/config-raspi`:
  ```bash
  scp hermit@rasserv01:~/.kube/config ~/.kube/config-raspi
  ```
- Registry running (`registry/registry-setup.yaml` applied)

## Quick start

```bash
cd terraform/environments/raspi

terraform init
terraform plan
terraform apply
```

## Deploying a new service

1. **Build and push the image** to the local registry.
   Raspberry Pi 5 runs on ARM64 — the image must target that architecture:
   ```bash
   docker buildx build --platform linux/arm64 -t rasserv01:30500/my-service:1.0.0 --push .
   ```
   If you build on an ARM64 machine (Apple Silicon, another Pi) you can use plain `docker build`:
   ```bash
   docker build -t rasserv01:30500/my-service:1.0.0 .
   docker push rasserv01:30500/my-service:1.0.0
   ```

2. **Add a module block** to `environments/raspi/main.tf`:
   ```hcl
   module "my_service" {
     source = "../../modules/raspi-k8s"

     app_name  = "my-service"
     namespace = "default"
     image     = "${var.registry}/my-service:1.0.0"
     replicas  = 2

     ports = [
       {
         name           = "http"
         container_port = 3000
         service_port   = 3000
         node_port      = 30900
       }
     ]

     env = {
       DATABASE_URL = "postgres://..."
     }

     resources = {
       requests = { cpu = "200m", memory = "256Mi" }
       limits   = { cpu = "1000m", memory = "512Mi" }
     }
   }
   ```

3. **Apply**:
   ```bash
   terraform apply
   ```

## Module reference (`raspi-k8s`)

### Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `app_name` | string | required | Resource name and label selector |
| `namespace` | string | `"default"` | Target namespace |
| `create_namespace` | bool | `false` | Create the namespace if absent |
| `image` | string | required | Full image reference |
| `replicas` | number | `1` | Pod replica count |
| `ports` | list(object) | required | Ports (name, container_port, service_port, node_port?) |
| `service_type` | string | `"NodePort"` | `ClusterIP`, `NodePort`, or `LoadBalancer` |
| `env` | map(string) | `{}` | Container environment variables |
| `resources` | object | 100m/128Mi req, 500m/512Mi lim | CPU and memory bounds |
| `node_selector` | map(string) | `{}` | Schedule pods only on matching nodes |
| `volumes` | list(object) | `[]` | Persistent volumes (see below) |

#### `volumes` object fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Volume name (also used as PV/PVC suffix) |
| `mount_path` | string | required | Path inside the container |
| `host_path` | string | required | Absolute path on the node, under `/mnt/storage/` |
| `size` | string | `"10Gi"` | Storage size |
| `access_mode` | string | `"ReadWriteOnce"` | K8s access mode |

### Outputs

| Output | Description |
|--------|-------------|
| `namespace` | Namespace the app landed in |
| `deployment_name` | Deployment resource name |
| `service_name` | Service resource name |
| `node_ports` | `{ "http" = 30800, … }` — empty for ClusterIP |
| `cluster_ip` | ClusterIP assigned to the Service |

## Notes

- **NodePort range** — K8s reserves 30000–32767. Pick ports that don't clash
  with existing services (registry is on 30500, Grafana is assigned by Prometheus stack).
- **Persistent volumes** — `host_path` must be under `/mnt/storage/` so data
  lands on the iSCSI LUN, not the SD card. Use `node_selector` to pin the pod
  to the node that owns the directory when data must not move between nodes.
- **Image tags** — prefer explicit version tags over `latest` in production-like
  deployments; `latest` makes `terraform plan` unable to detect image changes.
