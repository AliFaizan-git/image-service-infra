output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "service_names" {
  value = { for k, s in aws_ecs_service.this : k => s.name }
}