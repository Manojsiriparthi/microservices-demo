# ============================================================================
# IAM MODULE
# ============================================================================
#
# Responsibilities:
#   - Bastion host role + instance profile
#   - EKS cluster control-plane role
#   - EKS node group role (minimum required policies only)
#   - KMS key for EKS secrets encryption at rest
#
# NOT here (belongs in 2-eks-addons via IRSA):
#   - EBS CSI driver policy  -> 2-eks-addons/ebs-csi-driver.tf
#   - EFS CSI driver policy  -> 2-eks-addons (if added)
#   - Any other addon IRSA roles
# ============================================================================

# ============================================================================
# BASTION HOST
# ============================================================================

resource "aws_iam_role" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-role"
  description = "Role for bastion EC2 instance - SSM access only"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-role"
  })
}

# SSM Session Manager - allows secure shell without opening port 22 publicly
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-profile"
  })
}

# ============================================================================
# EKS CLUSTER CONTROL-PLANE ROLE
# ============================================================================

resource "aws_iam_role" "eks_cluster" {
  name        = "${var.project_name}-${var.environment}-eks-cluster-role"
  description = "Role assumed by the EKS control plane"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
  })
}

# Required: core EKS cluster permissions
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Required: allows EKS to manage ENIs for pod networking (VPC CNI)
resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ============================================================================
# EKS NODE GROUP ROLE
# Minimum policies required for nodes to join the cluster and run pods.
# Addon-specific permissions (EBS CSI, EFS CSI, etc.) are handled via
# IRSA in 2-eks-addons - NOT attached here to follow least-privilege.
# ============================================================================

resource "aws_iam_role" "eks_nodes" {
  name        = "${var.project_name}-${var.environment}-eks-node-role"
  description = "Role assumed by all EKS worker nodes (EC2)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-node-role"
  })
}

# Required: allows node to register with cluster, describe cluster resources
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Required: allows VPC CNI plugin to manage pod networking (ENI allocation)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Required: allows nodes to pull images from ECR
resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Operational: SSM Session Manager access on nodes (no bastion needed for debugging)
resource "aws_iam_role_policy_attachment" "eks_ssm_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Operational: allows CloudWatch agent on nodes to push metrics and logs
resource "aws_iam_role_policy_attachment" "eks_cloudwatch_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ============================================================================
# KMS KEY - EKS SECRETS ENCRYPTION AT REST
# Encrypts all Kubernetes Secrets stored in etcd.
# ============================================================================

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-secrets-key"
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

resource "aws_kms_key_policy" "eks_secrets" {
  key_id = aws_kms_key.eks_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account full access - required so the key is never locked out
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # EKS control plane needs these to encrypt/decrypt secrets in etcd
        Sid    = "AllowEKSControlPlane"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}

# Used in KMS key policy above
data "aws_caller_identity" "current" {}
