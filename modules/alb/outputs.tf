output "dns_name" {
  value = aws_lb.this.dns_name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.this : k => tg.arn }

}