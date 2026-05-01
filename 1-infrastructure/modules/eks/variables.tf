variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ) — used by all node groups"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs — included in cluster subnet list for ALB discovery"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN for EKS control plane"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for all EKS node groups"
  type        = string
}

variable "eks_secrets_kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption at rest"
  type        = string
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to send to CloudWatch"
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
  description = "Desired number of general nodes (spread across AZs)"
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
# DATABASE NODE GROUP — stateful workloads (taint: workload=database:NoSchedule)
# ============================================================================

variable "database_node_instance_types" {
  description = "Instance types for database nodes (memory-optimised recommended)"
  type        = list(string)
  default     = ["r6i.xlarge"]
}

variable "database_node_desired_size" {
  description = "Desired number of database nodes (one per AZ)"
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
  description = "Root EBS volume size (GB) for database nodes"
  type        = number
  default     = 100
}

# ============================================================================
# GPU NODE GROUP — AI/ML workloads (taint: workload=gpu:NoSchedule)
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
  description = "Minimum number of GPU nodes (0 = scale to zero when idle)"
  type        = number
  default     = 0
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 3
}

variable "gpu_node_disk_size" {
  description = "Root EBS volume size (GB) for GPU nodes"
  type        = number
  default     = 100
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
