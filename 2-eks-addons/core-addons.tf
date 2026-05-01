# ============================================================================
# CORE EKS MANAGED ADDONS
# ============================================================================
# These are the foundational addons every EKS cluster needs.
# Managed here (layer 2) so they can be version-pinned and updated
# independently from the cluster infrastructure (layer 1).
#
# Check latest versions:
#   aws eks describe-addon-versions --kubernetes-version 1.32 --addon-name <name>
# ============================================================================

# ============================================================================
# VPC CNI
# Provides pod networking — assigns VPC IPs directly to pods.
# Prefix delegation enabled: each node gets a /28 prefix → more pods per node.
# ============================================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = local.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.18.1-eksbuild.3"
  resolve_conflicts_on_update = "PRESERVE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"  # each node gets a /28 prefix → more pods per node
      WARM_PREFIX_TARGET       = "1"
    }
  })

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-vpc-cni" })
}

# ============================================================================
# KUBE-PROXY
# Maintains network rules on nodes for Kubernetes Service routing.
# ============================================================================

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = local.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.32.0-eksbuild.2"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-kube-proxy" })
}

# ============================================================================
# COREDNS
# Cluster DNS — resolves service names to ClusterIPs inside the cluster.
# ============================================================================

resource "aws_eks_addon" "coredns" {
  cluster_name                = local.cluster_name
  addon_name                  = "coredns"
  addon_version               = "v1.11.3-eksbuild.2"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-coredns" })
}

# ============================================================================
# EKS POD IDENTITY AGENT
# Allows pods to assume IAM roles without IRSA annotation on service accounts.
# Modern replacement for IRSA — supported on EKS 1.24+.
# ============================================================================

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = local.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = "v1.3.4-eksbuild.1"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-pod-identity" })
}
