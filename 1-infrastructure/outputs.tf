# ============================================================================
# INFRASTRUCTURE OUTPUTS
# ============================================================================

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# Bastion Outputs
output "bastion_instance_id" {
  description = "Bastion instance ID — connect via: aws ssm start-session --target <id>"
  value       = module.ec2_bastion.bastion_instance_id
}

# EKS Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA (without https://)"
  value       = module.eks.cluster_oidc_issuer_url
}

# IAM outputs consumed by 2-eks-addons
output "eks_node_role_name" {
  description = "EKS node IAM role name — used by 2-eks-addons to attach addon IRSA policies"
  value       = module.iam.eks_node_role_name
}
