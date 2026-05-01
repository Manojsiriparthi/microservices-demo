# ============================================================================
# EKS ADDONS OUTPUTS
# ============================================================================

# ── OIDC ─────────────────────────────────────────────────────────────────────

output "oidc_provider_arn" {
  description = "OIDC provider ARN — used by any new IRSA role"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# ── IAM ROLE ARNs ─────────────────────────────────────────────────────────────

output "ebs_csi_role_arn" {
  description = "EBS CSI driver IAM role ARN"
  value       = aws_iam_role.ebs_csi.arn
}

output "aws_lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM role ARN"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "karpenter_role_arn" {
  description = "Karpenter IAM role ARN"
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_interruption_queue_url" {
  description = "Karpenter SQS interruption queue URL"
  value       = aws_sqs_queue.karpenter_interruption.url
}

output "cloudwatch_observability_role_arn" {
  description = "CloudWatch Observability IAM role ARN"
  value       = aws_iam_role.cloudwatch_observability.arn
}

output "fluent_bit_role_arn" {
  description = "Fluent Bit IAM role ARN"
  value       = aws_iam_role.fluent_bit.arn
}

output "external_dns_role_arn" {
  description = "External DNS IAM role ARN"
  value       = aws_iam_role.external_dns.arn
}

output "cert_manager_role_arn" {
  description = "Cert Manager IAM role ARN"
  value       = aws_iam_role.cert_manager.arn
}

# ── NAMESPACES ────────────────────────────────────────────────────────────────

output "namespaces" {
  description = "All created Kubernetes namespaces"
  value = {
    # Per-app namespaces (3 per app: workload, database, monitoring)
    app1            = kubernetes_namespace.app1.metadata[0].name
    app1_database   = kubernetes_namespace.app1_database.metadata[0].name
    app1_monitoring = kubernetes_namespace.app1_monitoring.metadata[0].name
    app2            = kubernetes_namespace.app2.metadata[0].name
    app2_database   = kubernetes_namespace.app2_database.metadata[0].name
    app2_monitoring = kubernetes_namespace.app2_monitoring.metadata[0].name
    app3            = kubernetes_namespace.app3.metadata[0].name
    app3_database   = kubernetes_namespace.app3_database.metadata[0].name
    app3_monitoring = kubernetes_namespace.app3_monitoring.metadata[0].name
    app4            = kubernetes_namespace.app4.metadata[0].name
    app4_database   = kubernetes_namespace.app4_database.metadata[0].name
    app4_monitoring = kubernetes_namespace.app4_monitoring.metadata[0].name
    # Shared infra — platform-team + sre-team
    monitoring      = kubernetes_namespace.monitoring.metadata[0].name
    data            = kubernetes_namespace.data.metadata[0].name
    ai_ml           = kubernetes_namespace.ai_ml.metadata[0].name
    tools           = kubernetes_namespace.tools.metadata[0].name
  }
}

# ── INGRESSCLASS ──────────────────────────────────────────────────────────────

output "ingress_classes" {
  description = "IngressClass names for ALB routing"
  value = {
    external = kubernetes_ingress_class_v1.alb_external.metadata[0].name  # internet-facing ALB
    internal = kubernetes_ingress_class_v1.alb_internal.metadata[0].name  # internal ALB
  }
}

# ── CLOUDWATCH LOG GROUPS ─────────────────────────────────────────────────────

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for EKS cluster"
  value = {
    application = aws_cloudwatch_log_group.application.name
    dataplane   = aws_cloudwatch_log_group.dataplane.name
  }
}

# ── CORE ADDON VERSIONS ───────────────────────────────────────────────────────

output "core_addon_versions" {
  description = "Installed versions of core EKS managed addons"
  value = {
    vpc_cni                  = aws_eks_addon.vpc_cni.addon_version
    kube_proxy               = aws_eks_addon.kube_proxy.addon_version
    coredns                  = aws_eks_addon.coredns.addon_version
    pod_identity             = aws_eks_addon.pod_identity.addon_version
    ebs_csi_driver           = aws_eks_addon.ebs_csi_driver.addon_version
    cloudwatch_observability = aws_eks_addon.cloudwatch_observability.addon_version
  }
}
