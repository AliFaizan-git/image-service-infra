locals {
  backend_port  = 3001
  frontend_port = 3000

  ecr_backend  = module.ecr.repository_urls["${var.project}/backend"]
  ecr_frontend = module.ecr.repository_urls["${var.project}/frontend"]
}

module "alb" {
  source = "../../modules/alb"

  name              = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids
  default_service   = "frontend"

  services = {
    backend = {
      port              = local.backend_port
      health_check_path = "/health"
      priority          = 10
      stickiness        = true
      path_patterns     = ["/auth/*", "/images/*", "/internal/*", "/health", "/socket.io/*"]
    }
    frontend = {
      port              = local.frontend_port
      health_check_path = "/"
      path_patterns     = []
    }
  }
}

# Backend ki apni AWS permissions: images bucket
data "aws_iam_policy_document" "backend_task" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.s3_images.bucket_arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.s3_images.bucket_arn]
  }
}

module "ecs" {
  source = "../../modules/ecs"

  name                  = local.name_prefix
  region                = var.region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  secret_arns           = [module.rds.master_secret_arn]

  services = {
    backend = {
      image            = "${local.ecr_backend}:${var.image_tag}"
      port             = local.backend_port
      target_group_arn = module.alb.target_group_arns["backend"]
      desired_count    = var.desired_count

      # Env var NAAM apne backend code ke hisaab se rakho, ye placeholders hain
      environment = {
        NODE_ENV    = var.environment
        PORT        = tostring(local.backend_port)
        NOTIFY_MODE = "api"
        DB_HOST     = module.rds.address
        DB_PORT     = tostring(module.rds.port)
        DB_NAME     = module.rds.db_name
        S3_BUCKET   = module.s3_images.bucket_name
        AWS_REGION  = var.region
      }

      # Secrets Manager se, plain env mein kabhi nahi
      secrets = {
        DB_USER     = "${module.rds.master_secret_arn}:username::"
        DB_PASSWORD = "${module.rds.master_secret_arn}:password::"
      }
    }

    frontend = {
      image            = "${local.ecr_frontend}:${var.image_tag}"
      port             = local.frontend_port
      target_group_arn = module.alb.target_group_arns["frontend"]
      desired_count    = var.desired_count
    }
  }

  task_role_policies = {
    backend = data.aws_iam_policy_document.backend_task.json
  }

  # Target group ko listener rule se associate hona zaroori hai service banne se pehle
  depends_on = [module.alb]
}

# Glue rule: RDS sirf ECS SG se 5432 pe baat kare
resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.ecs.security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}