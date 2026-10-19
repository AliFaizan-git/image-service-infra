locals {
  ecr_lambda = module.ecr.repository_urls["image-processor/lambda"]
}

resource "random_password" "callback_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "callback" {
  name                    = "${local.name_prefix}/callback-secret"
  description             = "Shared secret: Lambda to backend /internal callback"
  recovery_window_in_days = var.allow_force_destroy ? 0 : 7
}

# Plain string (not JSON): the backend gets the whole SecretString injected as
# LAMBDA_API_KEY, and the Lambda reads the same value via CALLBACK_SECRET_ARN.
resource "aws_secretsmanager_secret_version" "callback" {
  secret_id     = aws_secretsmanager_secret.callback.id
  secret_string = random_password.callback_secret.result
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

  # Secret version must exist before the function can read it at runtime.
  depends_on = [aws_secretsmanager_secret_version.callback]
}
