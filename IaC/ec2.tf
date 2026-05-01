######################################
# SSH Key Pair (auto-generated)
######################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "mongo" {
  key_name   = "mongo-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

######################################
# Security Group — MongoDB VM
######################################
resource "aws_security_group" "mongo_sg" {
  name        = "mongo-sg"
  description = "Security group for MongoDB VM"
  vpc_id      = aws_vpc.main.id

  # ⚠ Intentional: SSH open to the world
  ingress {
    description = "SSH from anywhere (intentional misconfig)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MongoDB — restricted to EKS private subnets only
  ingress {
    description = "MongoDB from K8s private subnets only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [
      aws_subnet.private_a.cidr_block, # 10.0.11.0/24
      aws_subnet.private_c.cidr_block  # 10.0.12.0/24
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mongo-sg"
  }
}

######################################
# EC2 Instance — MongoDB Server
######################################
resource "aws_instance" "mongo" {
  ami                         = "ami-0735c191cf914754d" # Ubuntu 22.04 LTS (2022年リリース)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.mongo.key_name

  vpc_security_group_ids = [aws_security_group.mongo_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(templatefile("${path.module}/scripts/mongo_setup.sh", {
    mongo_admin_user = var.mongo_admin_user
    mongo_admin_pass = var.mongo_admin_pass
    mongo_app_user   = var.mongo_app_user
    mongo_app_pass   = var.mongo_app_pass
    mongo_app_db     = var.mongo_app_db
    s3_bucket        = aws_s3_bucket.backup.bucket
    aws_region       = var.aws_region
  }))

  tags = {
    Name = "mongo-instance"
  }

  depends_on = [aws_s3_bucket.backup]
}

######################################
# SSM Parameters — for K8s deployment
######################################
resource "aws_ssm_parameter" "mongo_private_ip" {
  name  = "/app/mongo/private_ip"
  type  = "String"
  value = aws_instance.mongo.private_ip
}

resource "aws_ssm_parameter" "mongo_app_user" {
  name  = "/app/mongo/app_user"
  type  = "String"
  value = var.mongo_app_user
}

resource "aws_ssm_parameter" "mongo_app_pass" {
  name  = "/app/mongo/app_pass"
  type  = "SecureString"
  value = var.mongo_app_pass
}

resource "aws_ssm_parameter" "mongo_app_db" {
  name  = "/app/mongo/app_db"
  type  = "String"
  value = var.mongo_app_db
}
