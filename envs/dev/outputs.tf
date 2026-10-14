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
  value = module.s3.bucket_name
}