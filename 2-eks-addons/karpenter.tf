# ============================================================================
# KARPENTER — NODE AUTOPROVISIONER
# ============================================================================
# Karpenter replaces Cluster Autoscaler. Instead of scaling pre-defined
# node groups, Karpenter provisions individual EC2 instances directly
# based on pending pod requirements.
#
# Why Karpenter over Cluster Autoscaler:
#   - 30-60s node provisioning vs 3-5 minutes
#   - Picks cheapest instance type that fits the workload automatically
#   - Built-in Spot + On-Demand fallback
#   - Aggressive node consolidation (removes underutilized nodes)
#   - No need to pre-define node groups per instance type
#
# Architecture:
#   - Karpenter controller runs on the existing general node group
#   - NodePool defines WHAT nodes Karpenter can provision
#   - EC2NodeClass defines HOW nodes are configured (AMI, subnet, SG)
#   - 3 NodePools: general, database, gpu — matching our node group taints
# ============================================================================

data "aws_caller_identity" "current" {}

# ── KARPENTER IAM ROLE (IRSA) ─────────────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_assume_role" {
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
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "${var.project_name}-${var.environment}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-karpenter"
  })
}

# Karpenter needs to create/terminate EC2 instances, manage ENIs, etc.
data "aws_iam_policy_document" "karpenter_policy" {
  # EC2 instance lifecycle management
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateFleet",
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSpotPriceHistory",
    ]
    resources = ["*"]
  }

  # Pass IAM role to EC2 instances
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # Instance profile for nodes
  statement {
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  # SSM for AMI discovery (EKS optimized AMIs)
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"]
  }

  # EKS cluster info
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"]
  }

  # Pricing API for spot instance selection
  statement {
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # SQS for interruption handling (spot termination notices)
  statement {
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_policy" "karpenter" {
  name        = "${var.project_name}-${var.environment}-karpenter"
  description = "Karpenter node provisioner permissions"
  policy      = data.aws_iam_policy_document.karpenter_policy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-karpenter"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# ── NODE INSTANCE PROFILE ─────────────────────────────────────────────────────
# Karpenter-provisioned nodes need an instance profile to assume the node role

data "aws_iam_role" "node_role" {
  name = data.terraform_remote_state.infrastructure.outputs.eks_node_role_name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.project_name}-${var.environment}-karpenter-node"
  role = data.aws_iam_role.node_role.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-karpenter-node"
  })
}

# ── SPOT INTERRUPTION HANDLING ────────────────────────────────────────────────
# SQS queue receives EC2 spot interruption notices, rebalance recommendations,
# and instance state change events. Karpenter drains nodes gracefully.

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.project_name}-${var.environment}-karpenter"
  message_retention_seconds = 300  # 5 minutes — interruption notices are time-sensitive
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-karpenter-interruption"
  })
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

# EventBridge rules to forward interruption events to SQS
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${var.project_name}-${var.environment}-karpenter-spot"
  description = "Karpenter — EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${var.project_name}-${var.environment}-karpenter-rebalance"
  description = "Karpenter — EC2 Instance Rebalance Recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule = aws_cloudwatch_event_rule.karpenter_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  name        = "${var.project_name}-${var.environment}-karpenter-instance-state"
  description = "Karpenter — EC2 Instance State Change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# ── KARPENTER NAMESPACE ───────────────────────────────────────────────────────

resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = {
      "app.kubernetes.io/name" = "karpenter"
      "managed-by"             = "terraform"
    }
  }
}

# ── HELM RELEASE ──────────────────────────────────────────────────────────────

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = kubernetes_namespace.karpenter.metadata[0].name
  version    = "1.0.6"

  values = [
    yamlencode({
      settings = {
        clusterName       = local.cluster_name
        interruptionQueue = aws_sqs_queue.karpenter_interruption.name
      }

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter.arn
        }
      }

      # HA — 2 replicas with leader election
      replicas = 2

      controller = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      # Run Karpenter controller on the existing general managed node group
      # (not on Karpenter-provisioned nodes — avoids chicken-and-egg problem)
      nodeSelector = { "node-type" = "general" }

      # Tolerate nothing — Karpenter must run on stable managed nodes
      tolerations = []

      priorityClassName = "system-cluster-critical"

      logLevel = "info"
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.karpenter,
    aws_iam_instance_profile.karpenter_node,
    kubernetes_namespace.karpenter,
  ]
}

# ── EC2NODECLASS — defines HOW nodes are configured ──────────────────────────
# Shared by all NodePools. Sets AMI, subnet discovery, SG discovery.

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      # Use EKS optimized AL2023 AMI — auto-updated by Karpenter
      amiFamily: AL2023

      # Discover subnets tagged for this cluster (private subnets only)
      subnetSelectorTerms:
        - tags:
            kubernetes.io/cluster/${local.cluster_name}: shared
            kubernetes.io/role/internal-elb: "1"

      # Discover security groups tagged for this cluster
      securityGroupSelectorTerms:
        - tags:
            kubernetes.io/cluster/${local.cluster_name}: owned

      # Instance profile for nodes to assume the node IAM role
      instanceProfile: ${aws_iam_instance_profile.karpenter_node.name}

      # EBS root volume — encrypted gp3
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true

      # IMDSv2 required
      metadataOptions:
        httpEndpoint: enabled
        httpProtocolIPv6: disabled
        httpPutResponseHopLimit: 1
        httpTokens: required

      tags:
        Name: ${var.project_name}-${var.environment}-karpenter-node
        ManagedBy: karpenter
  YAML

  depends_on = [helm_release.karpenter]
}

# ── NODEPOOL 1 — GENERAL ──────────────────────────────────────────────────────
# Provisions nodes for general application workloads.
# Uses Spot first, falls back to On-Demand.

resource "kubectl_manifest" "karpenter_nodepool_general" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: general
    spec:
      template:
        metadata:
          labels:
            node-type: general
            environment: ${var.environment}
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          # No taints — accepts all pods without tolerations
          taints: []

          requirements:
            # Prefer Spot, fall back to On-Demand automatically
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]

            # General purpose instance families (cost-optimised)
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - t3.large
                - t3.xlarge
                - t3a.large
                - t3a.xlarge
                - m5.large
                - m5.xlarge
                - m5a.large
                - m5a.xlarge
                - m6i.large
                - m6i.xlarge

            # All 3 AZs for HA
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ${var.aws_region}a
                - ${var.aws_region}b
                - ${var.aws_region}c

            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]

            - key: kubernetes.io/os
              operator: In
              values: ["linux"]

      # Node consolidation — remove underutilized nodes aggressively
      disruption:
        consolidationPolicy: WhenUnderutilized
        consolidateAfter: 30s

      # Limits — prevent runaway scaling
      limits:
        cpu: "100"       # max 100 vCPUs across all general nodes
        memory: "400Gi"  # max 400 GiB RAM

      weight: 10  # lower weight = preferred over other node pools
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# ── NODEPOOL 2 — DATABASE ─────────────────────────────────────────────────────
# Provisions memory-optimised nodes for database workloads.
# On-Demand only — databases need stable nodes, not Spot.

resource "kubectl_manifest" "karpenter_nodepool_database" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: database
    spec:
      template:
        metadata:
          labels:
            node-type: database
            environment: ${var.environment}
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          # Taint — only database pods with matching toleration schedule here
          taints:
            - key: workload
              value: database
              effect: NoSchedule

          requirements:
            # On-Demand only — databases must not be interrupted
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]

            # Memory-optimised instance families
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - r6i.large
                - r6i.xlarge
                - r6i.2xlarge
                - r6a.large
                - r6a.xlarge
                - r5.large
                - r5.xlarge

            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ${var.aws_region}a
                - ${var.aws_region}b
                - ${var.aws_region}c

            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]

            - key: kubernetes.io/os
              operator: In
              values: ["linux"]

      # Conservative consolidation for databases
      disruption:
        consolidationPolicy: WhenEmpty  # only remove completely empty nodes
        consolidateAfter: 5m

      limits:
        cpu: "48"
        memory: "192Gi"

      weight: 20
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# ── NODEPOOL 3 — GPU / AI-ML ──────────────────────────────────────────────────
# Provisions GPU nodes for AI/ML workloads.
# Scales to zero when no GPU jobs are running.

resource "kubectl_manifest" "karpenter_nodepool_gpu" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gpu
    spec:
      template:
        metadata:
          labels:
            node-type: gpu
            environment: ${var.environment}
            nvidia.com/gpu: "true"
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          # Taint — only GPU pods with matching toleration schedule here
          taints:
            - key: workload
              value: gpu
              effect: NoSchedule

          requirements:
            # Spot for GPU — significant cost savings (up to 70%)
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]

            # GPU instance families
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - g4dn.xlarge
                - g4dn.2xlarge
                - g4dn.4xlarge
                - g5.xlarge
                - g5.2xlarge
                - p3.2xlarge

            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ${var.aws_region}a
                - ${var.aws_region}b
                - ${var.aws_region}c

            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]

            - key: kubernetes.io/os
              operator: In
              values: ["linux"]

      # Remove GPU nodes immediately when empty (expensive instances)
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 1m

      limits:
        cpu: "64"
        memory: "256Gi"

      weight: 30
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
