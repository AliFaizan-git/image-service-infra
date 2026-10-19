# JWT signing key. Generated here so the ECS task never starts with an empty
# secret. NOTE: the value is stored in Terraform state in plaintext.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name_prefix}/app"
  description             = "App secrets (JSON): jwt_secret"
  recovery_window_in_days = var.allow_force_destroy ? 0 : 7
}

# ECS references this secret as "<arn>:jwt_secret::", so the value must be a
# JSON object with a "jwt_secret" key.
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    jwt_secret = random_password.jwt_secret.result
  })
}
