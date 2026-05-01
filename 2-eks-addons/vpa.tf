# ============================================================================
# VERTICAL POD AUTOSCALER (VPA)
# ============================================================================
# Automatically right-sizes pod CPU/memory requests based on actual usage.
#
# Works alongside HPA:
#   HPA — scales OUT (more pods) based on CPU/memory/custom metrics
#   VPA — scales UP (bigger pods) by adjusting resource requests
#
# Modes per workload:
#   "Off"    — only recommends, never changes (safe for production initially)
#   "Auto"   — automatically updates requests (requires pod restart)
#   "Initial"— sets requests only at pod creation, never updates running pods
# ============================================================================

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  namespace  = "kube-system"
  version    = "4.4.6"

  values = [
    yamlencode({
      admissionController = {
        enabled  = true
        replicas = 2  # HA — webhook must be available for pod admission

        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "100m", memory = "256Mi" }
        }
      }

      recommender = {
        enabled  = true
        replicas = 1

        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "512Mi" }
        }

        # How far back to look at historical metrics
        extraArgs = {
          "storage"                          = "prometheus"
          "recommendation-margin-fraction"   = "0.15"  # add 15% buffer on top of recommendation
        }
      }

      updater = {
        enabled  = true
        replicas = 1

        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
      }

      nodeSelector = { "node-type" = "general" }
    })
  ]

  depends_on = [helm_release.metrics_server]
}
