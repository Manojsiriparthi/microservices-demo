# Common tags and cluster information
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
    CreatedBy   = var.created_by
    CostCenter  = var.cost_center
    Application = "ShopEase-Ecommerce"
  }

  cluster_name      = data.terraform_remote_state.infrastructure.outputs.cluster_name
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
  vpc_id            = data.terraform_remote_state.infrastructure.outputs.vpc_id
}
