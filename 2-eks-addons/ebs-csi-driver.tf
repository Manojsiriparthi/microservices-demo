# ============================================================================
# EBS CSI DRIVER IAM ROLE
# ============================================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project_name}-${var.environment}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ============================================================================
# EBS CSI DRIVER ADDON
# ============================================================================

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = local.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.26.1-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-ebs-csi-driver"
  })
}

# ============================================================================
# STORAGE CLASS
# ============================================================================

# Default storage class - gp3 with WaitForFirstConsumer
resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
    iops      = "3000"
    throughput = "125"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# High-performance storage class for databases
resource "kubernetes_storage_class" "ebs_gp3_high_perf" {
  metadata {
    name = "ebs-gp3-high-perf"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Retain"  # Retain for databases

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
    iops      = "16000"    # Maximum IOPS for gp3
    throughput = "1000"    # Maximum throughput for gp3
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# io2 storage class for mission-critical databases
resource "kubernetes_storage_class" "ebs_io2" {
  metadata {
    name = "ebs-io2"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Retain"

  parameters = {
    type      = "io2"
    encrypted = "true"
    fsType    = "ext4"
    iops      = "64000"    # io2 supports up to 64,000 IOPS
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}
