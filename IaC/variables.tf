variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "wiz-cluster"
}

variable "ecr_repository_name" {}
variable "aws_region" {}