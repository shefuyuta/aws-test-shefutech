######################################
# ECR Repository
######################################
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"     # :latest 上書き許可

  image_scanning_configuration {
    scan_on_push = true                # プッシュ時に脆弱性スキャン
  }

  force_delete = true                  # destroy 時にイメージごと削除
}

######################################
# Lifecycle Policy — 古いイメージ自動削除
######################################
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
