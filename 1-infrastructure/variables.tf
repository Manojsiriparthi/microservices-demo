# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

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
  description = "Owner email for resource tagging"
  type        = string
}

variable "created_by" {
  description = "Username who created the resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# ============================================================================
# VPC VARIABLES
# ============================================================================

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones — must have one per AZ for HA (3 for production)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks — one per AZ"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks — one per AZ"
  type        = list(string)
  default     = ["10.2.10.0/24", "10.2.20.0/24", "10.2.30.0/24"]
}

# ============================================================================
# BASTION VARIABLES
# ============================================================================

variable "bastion_instance_type" {
  description = "Bastion EC2 instance type"
  type        = string
  default     = "t3.micro"
}

# No key_name or allowed_cidrs — access is via SSM Session Manager only

# ============================================================================
# EKS VARIABLES
# ============================================================================

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.32"
}

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ============================================================================
# GENERAL NODE GROUP — application workloads (no taint)
# ============================================================================

variable "general_node_instance_types" {
  description = "Instance types for general application nodes"
  type        = list(string)
  default     = ["t3.large"]
}

variable "general_node_desired_size" {
  description = "Desired number of general nodes — spread across all AZs"
  type        = number
  default     = 3
}

variable "general_node_min_size" {
  description = "Minimum number of general nodes"
  type        = number
  default     = 3
}

variable "general_node_max_size" {
  description = "Maximum number of general nodes"
  type        = number
  default     = 9
}

# ============================================================================
# DATABASE NODE GROUP — taint: workload=database:NoSchedule
# Only pods with matching toleration schedule here.
# ============================================================================

variable "database_node_instance_types" {
  description = "Instance types for database nodes (memory-optimised recommended)"
  type        = list(string)
  default     = ["r6i.xlarge"]
}

variable "database_node_desired_size" {
  description = "Desired number of database nodes — one per AZ"
  type        = number
  default     = 3
}

variable "database_node_min_size" {
  description = "Minimum number of database nodes"
  type        = number
  default     = 3
}

variable "database_node_max_size" {
  description = "Maximum number of database nodes"
  type        = number
  default     = 6
}

variable "database_node_disk_size" {
  description = "Root EBS volume size in GB for database nodes"
  type        = number
  default     = 100
}

# ============================================================================
# GPU NODE GROUP — taint: workload=gpu:NoSchedule
# Only AI/ML pods with matching toleration schedule here.
# ============================================================================

variable "gpu_node_instance_types" {
  description = "Instance types for GPU nodes (g4dn / p3 family)"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_min_size" {
  description = "Minimum GPU nodes (0 = scale to zero when idle)"
  type        = number
  default     = 0
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 3
}

variable "gpu_node_disk_size" {
  description = "Root EBS volume size in GB for GPU nodes"
  type        = number
  default     = 100
}
