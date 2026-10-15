output "address" {
  description = "db host name"
  value       = aws_db_instance.this.address
}

output "db_name" {
  value = aws_db_instance.this.db_name

}
output "port" {
  value = aws_db_instance.this.port
}

output "username" {
  value = aws_db_instance.this.username

}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "master_secret_arn" {
  description = "AWS managed secrect arn"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
