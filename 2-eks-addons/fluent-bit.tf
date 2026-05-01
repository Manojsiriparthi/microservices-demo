# ============================================================================
# FLUENT BIT - CENTRALIZED LOGGING
# ============================================================================
# Collects and forwards logs from all pods to CloudWatch Logs

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${local.cluster_name}/application"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-application-logs"
  })
}

resource "aws_cloudwatch_log_group" "dataplane" {
  name              = "/aws/eks/${local.cluster_name}/dataplane"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-dataplane-logs"
  })
}

# Fluent Bit IAM Role
data "aws_iam_policy_document" "fluent_bit_assume_role" {
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
      values   = ["system:serviceaccount:amazon-cloudwatch:fluent-bit"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluent_bit" {
  name               = "${var.project_name}-${var.environment}-fluent-bit"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  })
}

# Fluent Bit Policy
data "aws_iam_policy_document" "fluent_bit_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "fluent_bit" {
  name        = "${var.project_name}-${var.environment}-fluent-bit"
  description = "Policy for Fluent Bit to write logs to CloudWatch"
  policy      = data.aws_iam_policy_document.fluent_bit_policy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  })
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = aws_iam_policy.fluent_bit.arn
}

# ============================================================================
# FLUENT BIT DEPLOYMENT
# ============================================================================

# Create amazon-cloudwatch namespace
resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
    labels = {
      "app.kubernetes.io/name" = "amazon-cloudwatch"
    }
  }
}

resource "helm_release" "fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  namespace  = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  version    = "0.1.32"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "fluent-bit"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.fluent_bit.arn
  }

  # CloudWatch configuration
  set {
    name  = "cloudWatch.enabled"
    value = "true"
  }

  set {
    name  = "cloudWatch.region"
    value = var.aws_region
  }

  set {
    name  = "cloudWatch.logGroupName"
    value = aws_cloudwatch_log_group.application.name
  }

  # Firehose disabled (using CloudWatch only)
  set {
    name  = "firehose.enabled"
    value = "false"
  }

  # Kinesis disabled
  set {
    name  = "kinesis.enabled"
    value = "false"
  }

  # Elasticsearch disabled
  set {
    name  = "elasticsearch.enabled"
    value = "false"
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

  # Tolerations to run on all nodes including persistent nodes
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  depends_on = [
    aws_iam_role_policy_attachment.fluent_bit,
    kubernetes_namespace.amazon_cloudwatch,
    aws_cloudwatch_log_group.application,
    aws_cloudwatch_log_group.dataplane
  ]
}
