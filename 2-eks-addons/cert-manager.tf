# ============================================================================
# CERT MANAGER - AUTOMATED TLS CERTIFICATE MANAGEMENT
# ============================================================================
# Automatically provisions and renews TLS certificates from Let's Encrypt

# Cert Manager IAM Role (for Route53 DNS validation)
data "aws_iam_policy_document" "cert_manager_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.project_name}-${var.environment}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cert-manager"
  })
}

# Cert Manager Policy (Route53 for DNS-01 challenge)
data "aws_iam_policy_document" "cert_manager_policy" {
  statement {
    effect = "Allow"
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZonesByName",
      "route53:ListHostedZones"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cert_manager" {
  name        = "${var.project_name}-${var.environment}-cert-manager"
  description = "Policy for Cert Manager Route53 DNS validation"
  policy      = data.aws_iam_policy_document.cert_manager_policy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cert-manager"
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager.arn
}

# ============================================================================
# CERT MANAGER DEPLOYMENT
# ============================================================================

# Create cert-manager namespace
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "app.kubernetes.io/name"    = "cert-manager"
      "app.kubernetes.io/instance" = "cert-manager"
    }
  }
}

# Install Cert Manager with CRDs
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = "v1.14.4"

  # Install CRDs
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Service account with IRSA
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "cert-manager"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cert_manager.arn
  }

  # High availability - 2 replicas
  set {
    name  = "replicaCount"
    value = "2"
  }

  # Resource limits
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  # Webhook configuration
  set {
    name  = "webhook.replicaCount"
    value = "2"
  }

  # CA Injector configuration
  set {
    name  = "cainjector.replicaCount"
    value = "2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cert_manager,
    kubernetes_namespace.cert_manager
  ]
}

# ============================================================================
# CLUSTER ISSUER - LET'S ENCRYPT PRODUCTION
# ============================================================================
# Creates a ClusterIssuer for Let's Encrypt production certificates
# NOTE: Uncomment and configure after setting up Route53 hosted zone

# resource "kubectl_manifest" "letsencrypt_prod" {
#   yaml_body = <<-YAML
#     apiVersion: cert-manager.io/v1
#     kind: ClusterIssuer
#     metadata:
#       name: letsencrypt-prod
#     spec:
#       acme:
#         server: https://acme-v02.api.letsencrypt.org/directory
#         email: ${var.owner_email}
#         privateKeySecretRef:
#           name: letsencrypt-prod
#         solvers:
#         - selector: {}
#           dns01:
#             route53:
#               region: ${var.aws_region}
#   YAML
#
#   depends_on = [helm_release.cert_manager]
# }

# ============================================================================
# CLUSTER ISSUER - LET'S ENCRYPT STAGING (for testing)
# ============================================================================

# resource "kubectl_manifest" "letsencrypt_staging" {
#   yaml_body = <<-YAML
#     apiVersion: cert-manager.io/v1
#     kind: ClusterIssuer
#     metadata:
#       name: letsencrypt-staging
#     spec:
#       acme:
#         server: https://acme-staging-v02.api.letsencrypt.org/directory
#         email: ${var.owner_email}
#         privateKeySecretRef:
#           name: letsencrypt-staging
#         solvers:
#         - selector: {}
#           dns01:
#             route53:
#               region: ${var.aws_region}
#   YAML
#
#   depends_on = [helm_release.cert_manager]
# }
