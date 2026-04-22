resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.ec2_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.private.id]
  }
}

resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_role_arn   = aws_iam_role.ec2_role.arn
  subnet_ids      = [aws_subnet.private.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}
