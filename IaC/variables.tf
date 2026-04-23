variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "wiz-cluster"
}

variable "ecr_repository_name" {
  default = "node-app"
}

variable "aws_region" {
  default = "ap-northeast-1"
}