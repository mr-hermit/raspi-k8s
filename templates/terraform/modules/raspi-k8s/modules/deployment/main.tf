locals {
  base_labels     = merge({ "app" = var.name, "managed-by" = "terraform" }, var.labels)
  selector_labels = { "app" = var.name }

  has_liveness  = var.liveness_probe_http_path != null || var.liveness_probe_exec != null
  has_readiness = var.readiness_probe_http_path != null || var.readiness_probe_exec != null

  resource_limits = merge(
    { memory = var.resources_limits_memory },
    var.resources_limits_cpu != null ? { cpu = var.resources_limits_cpu } : {}
  )
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.base_labels
    annotations = var.annotations
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector_labels
    }

    strategy {
      type = var.update_strategy
    }

    template {
      metadata {
        labels      = local.base_labels
        annotations = var.pod_annotations
      }

      spec {
        service_account_name             = var.service_account_name
        termination_grace_period_seconds = var.termination_grace_period_seconds
        node_selector                    = length(var.node_selector) > 0 ? var.node_selector : null

        dynamic "security_context" {
          for_each = var.pod_security_context != null ? [var.pod_security_context] : []
          content {
            run_as_user     = security_context.value.run_as_user
            run_as_group    = security_context.value.run_as_group
            fs_group        = security_context.value.fs_group
            run_as_non_root = security_context.value.run_as_non_root
          }
        }

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          command           = length(var.command) > 0 ? var.command : null
          args              = length(var.args) > 0 ? var.args : null

          dynamic "port" {
            for_each = var.ports
            content {
              name           = port.value.name
              container_port = port.value.container_port
              protocol       = coalesce(port.value.protocol, "TCP")
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = var.env_from_field_ref
            content {
              name = env.value.name
              value_from {
                field_ref {
                  field_path = env.value.field_path
                }
              }
            }
          }

          dynamic "env_from" {
            for_each = var.env_from_configmaps
            content {
              config_map_ref {
                name = env_from.value
              }
            }
          }

          dynamic "env_from" {
            for_each = var.env_from_secrets
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }

          resources {
            requests = {
              cpu    = var.resources_requests_cpu
              memory = var.resources_requests_memory
            }
            limits = local.resource_limits
          }

          dynamic "volume_mount" {
            for_each = var.volume_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              sub_path   = volume_mount.value.sub_path
              read_only  = volume_mount.value.read_only
            }
          }

          dynamic "liveness_probe" {
            for_each = local.has_liveness ? [1] : []
            content {
              initial_delay_seconds = var.liveness_probe_initial_delay
              period_seconds        = var.liveness_probe_period
              failure_threshold     = var.liveness_probe_failure_threshold

              dynamic "http_get" {
                for_each = var.liveness_probe_http_path != null ? [1] : []
                content {
                  path = var.liveness_probe_http_path
                  port = var.liveness_probe_http_port
                }
              }

              dynamic "exec" {
                for_each = var.liveness_probe_exec != null ? [1] : []
                content {
                  command = var.liveness_probe_exec
                }
              }
            }
          }

          dynamic "readiness_probe" {
            for_each = local.has_readiness ? [1] : []
            content {
              initial_delay_seconds = var.readiness_probe_initial_delay
              period_seconds        = var.readiness_probe_period
              failure_threshold     = var.readiness_probe_failure_threshold

              dynamic "http_get" {
                for_each = var.readiness_probe_http_path != null ? [1] : []
                content {
                  path = var.readiness_probe_http_path
                  port = var.readiness_probe_http_port
                }
              }

              dynamic "exec" {
                for_each = var.readiness_probe_exec != null ? [1] : []
                content {
                  command = var.readiness_probe_exec
                }
              }
            }
          }

          dynamic "security_context" {
            for_each = var.container_security_context != null ? [var.container_security_context] : []
            content {
              read_only_root_filesystem  = security_context.value.read_only_root_filesystem
              allow_privilege_escalation = security_context.value.allow_privilege_escalation
              run_as_user                = security_context.value.run_as_user
            }
          }
        }

        dynamic "volume" {
          for_each = var.volumes
          content {
            name = volume.value.name

            dynamic "persistent_volume_claim" {
              for_each = volume.value.pvc_claim_name != null ? [volume.value.pvc_claim_name] : []
              content {
                claim_name = persistent_volume_claim.value
              }
            }

            dynamic "config_map" {
              for_each = volume.value.config_map_name != null ? [volume.value.config_map_name] : []
              content {
                name = config_map.value
              }
            }

            dynamic "secret" {
              for_each = volume.value.secret_name != null ? [volume.value.secret_name] : []
              content {
                secret_name = secret.value
              }
            }

            dynamic "empty_dir" {
              for_each = volume.value.empty_dir ? [1] : []
              content {}
            }

            dynamic "host_path" {
              for_each = volume.value.host_path != null ? [1] : []
              content {
                path = volume.value.host_path
                type = volume.value.host_path_type
              }
            }
          }
        }
      }
    }
  }
}
