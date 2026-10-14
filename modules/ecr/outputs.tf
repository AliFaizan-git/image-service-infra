output "repository_urls" {
  value = { for name, r in aws_ecr_repository.this : name => r.repository_url }
}

output "repository_arns" {
  value = { for name, r in aws_ecr_repository.this : name => r.arn }
}