# ============================================================================
# OIDC PROVIDER
# Creates OIDC provider using EKS cluster output from Layer 1
# ============================================================================

# Get TLS certificate from EKS OIDC issuer
data "tls_certificate" "eks" {
  url = "https://${data.terraform_remote_state.infrastructure.outputs.cluster_oidc_issuer_url}"
}

# Create OIDC Provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = "https://${data.terraform_remote_state.infrastructure.outputs.cluster_oidc_issuer_url}"

  tags = local.common_tags
}
