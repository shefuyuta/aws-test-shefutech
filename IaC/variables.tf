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

######################################
# MongoDB
######################################
variable "mongo_admin_user" {
  default = "adminUser"
}

variable "mongo_admin_pass" {
  default = "WizAdmin2026!"
}

variable "mongo_app_user" {
  default = "appUser"
}

variable "mongo_app_pass" {
  default = "WizApp2026!"
}

variable "mongo_app_db" {
  default = "wizdb"
}
