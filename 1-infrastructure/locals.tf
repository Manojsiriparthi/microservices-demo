# Common tags applied to all resources
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

  cluster_name = "${var.project_name}-${var.environment}-cluster"
}
