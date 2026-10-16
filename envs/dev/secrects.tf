resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name_prefix}/app"
  description             = "App secrets (JSON): jwt_secret"
  recovery_window_in_days = var.allow_force_destroy ? 0 : 7
}