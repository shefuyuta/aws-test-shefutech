output "mongo_ip" {
  value = aws_instance.mongo.public_ip
}

output "s3_bucket" {
  value = aws_s3_bucket.backup.bucket
}
