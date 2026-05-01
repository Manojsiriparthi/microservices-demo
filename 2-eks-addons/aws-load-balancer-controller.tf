# ============================================================================
# AWS LOAD BALANCER CONTROLLER
# ============================================================================
# Manages AWS ALB/NLB from Kubernetes Ingress and Service resources.
#
# ALB strategy for this cluster:
#   External ALB (internet-facing):
#     - group.name: external-alb
#     - Path-based routing: /app1, /app2, /app3 ... → multiple apps, one ALB
#     - Example: alb.example.com/youtube, alb.example.com/netflix
#
#   Internal ALB (private):
#     - group.name: internal-alb
#     - Backend APIs + monitoring tools (Grafana, Prometheus, Kibana)
#     - Example: internal-alb/api, internal-alb/grafana, internal-alb/kibana
# ============================================================================

# ── IRSA ─────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.project_name}-${var.environment}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-aws-lb-controller"
  })
}

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "${var.project_name}-${var.environment}-aws-lb-controller"
  description = "AWS Load Balancer Controller — full ALB/NLB management"
  policy      = file("${path.module}/policies/aws-lb-controller-policy.json")

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-aws-lb-controller"
  })
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

# ── HELM RELEASE ──────────────────────────────────────────────────────────────

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.10.0"

  values = [
    yamlencode({
      clusterName = local.cluster_name
      region      = var.aws_region
      vpcId       = local.vpc_id  # required for target group binding

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn
        }
      }

      # HA — 2 replicas with leader election
      replicaCount = 2

      # Enable shield and WAF integration (optional — enable if using WAF)
      enableShield = false
      enableWaf    = false
      enableWafv2  = false

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }

      # Spread across AZs
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "DoNotSchedule"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/name" = "aws-load-balancer-controller"
            }
          }
        }
      ]

      nodeSelector = { "node-type" = "general" }

      priorityClassName = "system-cluster-critical"
    })
  ]

  depends_on = [aws_iam_role_policy_attachment.aws_lb_controller]
}

# ── INGRESSCLASS — EXTERNAL ALB ───────────────────────────────────────────────
# Use in Ingress: ingressClassName: alb-external
# Annotation:    alb.ingress.kubernetes.io/scheme: internet-facing
# Group:         alb.ingress.kubernetes.io/group.name: external-alb
# Result:        ONE internet-facing ALB shared across all apps in the group
#                Path-based: /app1 → svc1, /app2 → svc2, /app3 → svc3

resource "kubernetes_ingress_class_v1" "alb_external" {
  metadata {
    name = "alb-external"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "false"
    }
  }

  spec {
    controller = "ingress.k8s.aws/alb"
  }

  depends_on = [helm_release.aws_lb_controller]
}

# ── INGRESSCLASS — INTERNAL ALB ───────────────────────────────────────────────
# Use in Ingress: ingressClassName: alb-internal
# Annotation:    alb.ingress.kubernetes.io/scheme: internal
# Group:         alb.ingress.kubernetes.io/group.name: internal-alb
# Result:        ONE internal ALB shared by backend APIs + monitoring tools

resource "kubernetes_ingress_class_v1" "alb_internal" {
  metadata {
    name = "alb-internal"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "false"
    }
  }

  spec {
    controller = "ingress.k8s.aws/alb"
  }

  depends_on = [helm_release.aws_lb_controller]
}
