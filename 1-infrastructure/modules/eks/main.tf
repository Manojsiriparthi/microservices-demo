# ============================================================================
# EKS MODULE - PRODUCTION GRADE
# ============================================================================
#
# Security Group:
#   EKS automatically creates and manages the cluster security group.
#   It handles all control-plane <-> node and node <-> node traffic.
#   No custom SGs or launch templates needed.
#
# Node Groups:
#   1. general  — application workloads, no taint
#   2. database — only database pods (taint + label)
#   3. gpu      — only AI/ML pods (taint + label)
# ============================================================================

# ============================================================================
# EKS CLUSTER
# ============================================================================

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true            # nodes talk to API server privately inside VPC
    endpoint_public_access  = true            # kubectl access from bastion / CI-CD
    public_access_cidrs     = ["0.0.0.0/0"]  # PRODUCTION: restrict to your VPN/office CIDR
    # security_group_ids not set — EKS creates and manages the cluster SG automatically
  }

  # Encrypt all Kubernetes Secrets at rest in etcd
  encryption_config {
    provider {
      key_arn = var.eks_secrets_kms_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types  # full control plane audit trail in CloudWatch

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [access_config[0].bootstrap_cluster_creator_admin_permissions]
  }
}

# ============================================================================
# NODE GROUP 1 — GENERAL
#
# Purpose : general application workloads
# Taint   : none — accepts all pods by default
# Label   : node-type=general
# Subnets : all 3 private subnets → one node per AZ automatically
# ============================================================================

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-general-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.general_node_instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = 50  # GB — encrypted by default on EKS managed nodes

  scaling_config {
    desired_size = var.general_node_desired_size
    min_size     = var.general_node_min_size
    max_size     = var.general_node_max_size
  }

  update_config {
    max_unavailable_percentage = 33  # rolling update — max 1/3 unavailable at a time
  }

  labels = {
    node-type   = "general"
    environment = var.environment
  }

  # No taints — general nodes accept all pods

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-general-nodes"
  })

  depends_on = [aws_eks_cluster.main]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ============================================================================
# NODE GROUP 2 — DATABASE
#
# Purpose : stateful / database workloads only
# Taint   : workload=database:NoSchedule
#           → only pods with this toleration can schedule here
# Label   : node-type=database
#           → use nodeSelector: node-type: database in pod spec
# Subnets : all 3 private subnets → one node per AZ automatically
# ============================================================================

resource "aws_eks_node_group" "database" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-database-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.database_node_instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = var.database_node_disk_size  # larger disk for database storage

  scaling_config {
    desired_size = var.database_node_desired_size
    min_size     = var.database_node_min_size
    max_size     = var.database_node_max_size
  }

  update_config {
    max_unavailable = 1  # conservative — never take down more than 1 DB node at a time
  }

  labels = {
    node-type   = "database"
    environment = var.environment
  }

  # Only pods with toleration key=workload, value=database will schedule here
  taint {
    key    = "workload"
    value  = "database"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-nodes"
  })

  depends_on = [aws_eks_cluster.main]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ============================================================================
# NODE GROUP 3 — GPU / AI-ML
#
# Purpose : AI/ML workloads only
# Taint   : workload=gpu:NoSchedule
#           → only pods with this toleration can schedule here
# Label   : node-type=gpu
#           → use nodeSelector: node-type: gpu in pod spec
# Subnets : all 3 private subnets → spread across AZs
# min=0   : scales to zero when no GPU jobs are running (cost saving)
# ============================================================================

resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-gpu-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.gpu_node_instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = var.gpu_node_disk_size  # larger disk for model weights and CUDA libraries

  scaling_config {
    desired_size = var.gpu_node_desired_size
    min_size     = var.gpu_node_min_size  # 0 = scale to zero when idle
    max_size     = var.gpu_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type                       = "gpu"
    environment                     = var.environment
    "nvidia.com/gpu"                = "true"
    "k8s.amazonaws.com/accelerator" = "nvidia-tesla"
  }

  # Only pods with toleration key=workload, value=gpu will schedule here
  taint {
    key    = "workload"
    value  = "gpu"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-gpu-nodes"
  })

  depends_on = [aws_eks_cluster.main]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

