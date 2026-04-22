resource "aws_s3_bucket" "backup" {
  bucket = "wiz-backup-${random_id.rand.hex}"
}

resource "random_id" "rand" {
  byte_length = 4
}

resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.backup.id

  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = "*"
      Action = ["s3:GetObject","s3:ListBucket"]
      Resource = [
        aws_s3_bucket.backup.arn,
        "${aws_s3_bucket.backup.arn}/*"
      ]
    }]
  })
}