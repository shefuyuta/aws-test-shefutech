resource "aws_s3_bucket" "backup" {
  bucket = "wiz-backup-${random_id.rand.hex}"
}

resource "random_id" "rand" {
  byte_length = 4
}

# ★これが重要（Block Public Accessを解除）
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# ★ポリシー適用（depends_on推奨）
resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.backup.id

  depends_on = [
    aws_s3_bucket_public_access_block.backup
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = "*"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.backup.arn,
        "${aws_s3_bucket.backup.arn}/*"
      ]
    }]
  })
}
