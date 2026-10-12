output "state_bucket_name" {
    description = "Use this in every backend config"
    value = aws_s3_bucket.state.id
  
}

output "state_bucket_arn" {
  value = aws_s3_bucket.state.arn
}