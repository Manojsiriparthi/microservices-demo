# ============================================================================
# METRICS SERVER
# Provides real-time CPU/memory metrics for:
#   - HPA (Horizontal Pod Autoscaler) — scale pods on CPU/memory
#   - VPA (Vertical Pod Autoscaler)   — right-size pod resource requests
#   - kubectl top nodes / kubectl top pods
# ============================================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  values = [
    yamlencode({
      # HA — 2 replicas so HPA never loses metrics during rolling updates
      replicas = 2

      # Required for EKS — kubelet serving certs are not signed by cluster CA
      args = ["--kubelet-insecure-tls"]

      # PodDisruptionBudget — keep at least 1 replica during disruptions
      podDisruptionBudget = {
        enabled      = true
        minAvailable = 1
      }

      resources = {
        requests = { cpu = "100m", memory = "200Mi" }
        limits   = { cpu = "200m", memory = "400Mi" }
      }

      # Spread across AZs
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "DoNotSchedule"
          labelSelector = {
            matchLabels = { "app.kubernetes.io/name" = "metrics-server" }
          }
        }
      ]

      nodeSelector = { "node-type" = "general" }

      priorityClassName = "system-cluster-critical"
    })
  ]
}
