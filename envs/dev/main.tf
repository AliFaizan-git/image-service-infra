data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "image"
  region             = var.region
  vpc_cidr               = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 2)
  single_nat_gateway = var.single_nat_gateway
}

module "ecr" {
  source = "../../modules/ecr"

  repositories = [
    "${var.project}/backend",
    "${var.project}/frontend",
    "image-processor/lambda"
  ]
  force_delete = var.allow_force_destroy
}

module "s3" {
  source        = "../../modules/s3"
  bucket_name   = "${local.name_prefix}-images-${local.account_id}"
  force_destroy = var.allow_force_destroy
}