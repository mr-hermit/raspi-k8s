# ── raspi environment ─────────────────────────────────────────────────────────
#
# Add one module block per application you want to deploy.
# The registry variable is defined in variables.tf and set in terraform.tfvars.
#
# Workflow for each new service:
#   1. Build and push your image to the registry:
#        docker push rasserv01:30500/<app-name>:<tag>
#   2. Add a module block below (copy the sample-app block as a starting point).
#   3. terraform plan && terraform apply

# ── Sample application ────────────────────────────────────────────────────────
# A minimal deployment template. Rename, adjust ports/resources, and remove or
# uncomment the volumes block as needed.

module "sample_app" {
  source = "../../modules/raspi-k8s"

  app_name  = "sample-app"
  namespace = "default"
  image     = "${var.registry}/sample-app:latest"
  replicas  = 1

  ports = [
    {
      name           = "http"
      container_port = 8080
      service_port   = 8080
      node_port      = 30800
    }
  ]

  env = {
    APP_ENV = "raspi-lab"
  }

  resources = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }

  # Uncomment to mount a directory from the iSCSI volume.
  # host_path must exist on the node — the storage/iscsi-setup.yaml playbook
  # mounts /mnt/storage on every node.
  #
  # volumes = [
  #   {
  #     name       = "data"
  #     mount_path = "/app/data"
  #     host_path  = "/mnt/storage/sample-app/data"
  #     size       = "5Gi"
  #   }
  # ]
}
