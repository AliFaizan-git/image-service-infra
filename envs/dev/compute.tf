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
  vpc_cidr          = module.vpc_cidr
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
      port = local.frontend_port
      health_check_path = "/"
      path_patterns = []
    }
  }
}