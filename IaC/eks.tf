######################################
# EKS Cluster Role
######################################
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

######################################
# EKS Node Role
######################################
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "registry_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

######################################
# EKS Cluster (with Access Entry API enabled)
######################################
resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_c.id
    ]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Access Entry API を有効化(aws-auth ConfigMap よりモダンな方式)
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

######################################
# Node Group
######################################
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "wiz-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.registry_policy
  ]
}

######################################
# Access Entry — github-actions-role
# bootstrap_cluster_creator_admin_permissions = true により
# クラスタ作成者 (github-actions-role) には自動で Admin 権限が付与される
# 追加の Access Entry は不要
######################################

######################################
# Access Entry — odl_user_2202624 (デモ用)
# CloudShell から kubectl を実行するために必要
######################################
resource "aws_eks_access_entry" "cloudshell_admin" {
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = "arn:aws:iam::438465147858:user/odl_user_2202624"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cloudshell_admin" {
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = "arn:aws:iam::438465147858:user/odl_user_2202624"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cloudshell_admin]
}

######################################
# OIDC Provider (IRSA 用)
######################################
data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

######################################
# ALB Controller IAM Policy
######################################
resource "aws_iam_policy" "alb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/alb_iam_policy.json")
}

######################################
# ALB Controller IAM Role (IRSA)
######################################
resource "aws_iam_role" "alb_controller" {
  name = "alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.oidc.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

######################################
# SSM Parameter Store
######################################
resource "aws_ssm_parameter" "eks_cluster_name" {
  name  = "/app/eks/cluster_name"
  type  = "String"
  value = aws_eks_cluster.cluster.name
}

resource "aws_ssm_parameter" "ecr_repo" {
  name  = "/app/ecr/repository"
  type  = "String"
  value = var.ecr_repository_name
}

resource "aws_ssm_parameter" "region" {
  name  = "/app/aws/region"
  type  = "String"
  value = var.aws_region
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/app/eks/vpc_id"
  type  = "String"
  value = aws_vpc.main.id
}

resource "aws_ssm_parameter" "alb_role_arn" {
  name  = "/app/eks/alb_role_arn"
  type  = "String"
  value = aws_iam_role.alb_controller.arn
}
