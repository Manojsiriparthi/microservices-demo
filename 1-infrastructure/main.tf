# ============================================================================
# MAIN INFRASTRUCTURE - MODULE ORCHESTRATION
# ============================================================================
# Execution order (enforced by depends_on):
#   1. iam      — roles and KMS key (no dependencies)
#   2. vpc      — networking (no dependencies)
#   3. bastion  — needs vpc + iam
#   4. eks      — needs vpc + iam
# ============================================================================

# ── IAM ──────────────────────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags
}

# ── VPC ──────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = local.cluster_name
  common_tags          = local.common_tags
}

# ── BASTION ───────────────────────────────────────────────────────────────────
module "ec2_bastion" {
  source = "./modules/ec2-bastion"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_id         = module.vpc.private_subnet_ids[0]  # private subnet — SSM handles access
  instance_type             = var.bastion_instance_type
  iam_instance_profile_name = module.iam.bastion_instance_profile_name
  common_tags               = local.common_tags

  depends_on = [module.vpc, module.iam]
}

# ── EKS ───────────────────────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name            = var.project_name
  environment             = var.environment
  cluster_name            = local.cluster_name
  cluster_version         = var.cluster_version
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  public_subnet_ids       = module.vpc.public_subnet_ids
  cluster_role_arn        = module.iam.eks_cluster_role_arn
  node_role_arn           = module.iam.eks_node_role_arn
  eks_secrets_kms_key_arn = module.iam.eks_secrets_kms_key_arn
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # General nodes — application workloads, no taint
  general_node_instance_types = var.general_node_instance_types
  general_node_desired_size   = var.general_node_desired_size
  general_node_min_size       = var.general_node_min_size
  general_node_max_size       = var.general_node_max_size

  # Database nodes — taint: workload=database:NoSchedule
  database_node_instance_types = var.database_node_instance_types
  database_node_desired_size   = var.database_node_desired_size
  database_node_min_size       = var.database_node_min_size
  database_node_max_size       = var.database_node_max_size
  database_node_disk_size      = var.database_node_disk_size

  # GPU nodes — taint: workload=gpu:NoSchedule
  gpu_node_instance_types = var.gpu_node_instance_types
  gpu_node_desired_size   = var.gpu_node_desired_size
  gpu_node_min_size       = var.gpu_node_min_size
  gpu_node_max_size       = var.gpu_node_max_size
  gpu_node_disk_size      = var.gpu_node_disk_size

  common_tags = local.common_tags

  depends_on = [module.vpc, module.iam]
}
