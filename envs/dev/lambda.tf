locals {
  ecr_lambda = module.ecr.repository_urls["image-processor/lambda"]
}

resource "aws_secretsmanager_secret" "callback" {
  name                    = "${local.name_prefix}/callback-secret"
  description             = "Shared secret: Lambda to backend /internal callback"
  recovery_window_in_days = var.allow_force_destroy ? 0 : 7
}

module "lambda" {
  source = "../../modules/lambda"

  function_name = "${local.name_prefix}-image-processor"
  image_uri     = "${local.ecr_lambda}:${var.image_tag}"

  bucket_id   = module.s3_images.bucket_name
  bucket_arn  = module.s3_images.bucket_arn
  secret_arns = [aws_secretsmanager_secret.callback.arn]

  environment = {
    NOTIFY_MODE         = "api"
    BACKEND_URL         = "http://${module.alb.dns_name}"
    CALLBACK_SECRET_ARN = aws_secretsmanager_secret.callback.arn
  }
}