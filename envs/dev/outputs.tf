output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "name_prefix" {
  value = local.name_prefix
}

output "github_role_arns" {
  value = module.github_oidc.role_arns
}
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "images_bucket" {
  value = module.s3_images.bucket_name
}

output "rds_address" {
  value = module.rds.address
}

output "master_secret_arn" {
  value = module.rds.master_secret_arn
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}