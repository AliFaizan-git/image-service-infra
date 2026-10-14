locals {
  repos = {
    infra    = "image-service-infra"
    backend  = "image-service-backend"
    frontend = "image-service-frontend"
    lambda   = "image-processor-lambda"
  }

  gh = { for k, r in local.repos : k => "repo:${var.github_owner}/${r}" }
}

data "aws_iam_policy_document" "app" {
  for_each = toset(["backend", "frontend"])

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.project}/${each.key}"]
  }

  statement {
    sid       = "EcsTaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"] # in actions pe resource-level restriction supported nahi
  }

  statement {
    sid       = "EcsDeploy"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:${var.region}:${local.account_id}:service/${local.name_prefix}-cluster/${local.name_prefix}-${each.key}"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.name_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/image-processor/lambda"]
  }

  statement {
    sid = "LambdaDeploy"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
    ]
    resources = ["arn:aws:lambda:${var.region}:${local.account_id}:function:${local.name_prefix}-image-processor"]
  }
}

data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/${var.environment}/terraform.tfstate*"]
  }
}

module "github_oidc" {
  source       = "../../modules/github-oidc"
  name_prefix  = local.name_prefix
  github_owner = var.github_owner

  roles = {
    infra-plan = {
      subjects            = ["${local.gh.infra}:pull_request"]
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      policy_json         = data.aws_iam_policy_document.plan_state_lock.json
    }

    infra-apply = {
      subjects            = ["${local.gh.infra}:environment:${var.environment}"]
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    backend = {
      subjects            = ["${local.gh.backend}:ref:refs/heads/main"]
      managed_policy_arns = []
      policy_json         = data.aws_iam_policy_document.app["backend"].json
    }

    frontend = {
      subjects            = ["${local.gh.frontend}:ref:refs/heads/main"]
      managed_policy_arns = []

      policy_json = data.aws_iam_policy_document.app["frontend"].json
    }

    lambda = {
      subjects            = ["${local.gh.lambda}:ref:refs/heads/main"]
      managed_policy_arns = []

      policy_json = data.aws_iam_policy_document.lambda.json
    }
  }
}
