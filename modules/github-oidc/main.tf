resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprint_list

}

data "aws_iam_policy_document" "trust" {
  for_each = var.roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}*"]
    }

  }
}

resource "aws_iam_role" "this" {
  for_each             = var.roles
  name                 = "${var.name_prefix}-gh-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = var.max_session_duration
}

locals {
  managed_attachments = merge([
    for role, cfg in var.roles : {
      for arn in cfg.managed_policy_arns : "${role}|${arn}" => {
        role = role
        arn  = arn
      }
    }
  ]...)
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = local.managed_attachments

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}
resource "aws_iam_role_policy" "inline" {
  for_each = { for k, v in var.roles : k => v if v.policy_json != null }

  name   = "${var.name_prefix}-gh-${each.key}"
  role   = aws_iam_role.this[each.key].id
  policy = each.value.policy_json
}
