output "provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "role_arns" {
  description = "role key => ARN (GitHub workflows mein yahi use hoga)"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}