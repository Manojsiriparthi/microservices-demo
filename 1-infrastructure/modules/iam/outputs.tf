# ============================================================================
# IAM MODULE OUTPUTS
# ============================================================================

# ── Bastion ──────────────────────────────────────────────────────────────────

output "bastion_role_arn" {
  description = "Bastion IAM role ARN"
  value       = aws_iam_role.bastion.arn
}

output "bastion_instance_profile_name" {
  description = "Bastion instance profile name — passed to ec2-bastion module"
  value       = aws_iam_instance_profile.bastion.name
}

# ── EKS Cluster ──────────────────────────────────────────────────────────────

output "eks_cluster_role_arn" {
  description = "EKS control-plane IAM role ARN — passed to aws_eks_cluster"
  value       = aws_iam_role.eks_cluster.arn
}

# ── EKS Nodes ────────────────────────────────────────────────────────────────

output "eks_node_role_arn" {
  description = "EKS node group IAM role ARN — passed to all aws_eks_node_group resources"
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_node_role_name" {
  description = "EKS node group IAM role name — used by 2-eks-addons to attach addon-specific policies"
  value       = aws_iam_role.eks_nodes.name
}

# ── KMS ──────────────────────────────────────────────────────────────────────

output "eks_secrets_kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption — passed to eks module encryption_config"
  value       = aws_kms_key.eks_secrets.arn
}

output "eks_secrets_kms_key_id" {
  description = "KMS key ID — used for key policy references and CloudWatch"
  value       = aws_kms_key.eks_secrets.key_id
}
