locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-10-2026"
}

