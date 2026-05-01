variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "shopease"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "owner_email" {
  description = "Owner email"
  type        = string
}

variable "created_by" {
  description = "Created by username"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}
