output "mongo_public_ip" {
  description = "MongoDB VM public IP (for SSH access)"
  value       = aws_instance.mongo.public_ip
}

output "mongo_private_ip" {
  description = "MongoDB VM private IP (for K8s connection)"
  value       = aws_instance.mongo.private_ip
}

output "s3_bucket" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.backup.bucket
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.cluster.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.cluster.endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "ssh_private_key" {
  description = "SSH private key for mongo-instance (save to file, chmod 400)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
