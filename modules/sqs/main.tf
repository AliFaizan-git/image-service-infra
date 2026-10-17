data "aws_caller_identity" "current" {}

locals {
  suffix = var.fifo ? ".fifo" : "" # FIFO queue needs to be end in .fifo
}

# --- Dead-letter queue ---
resource "aws_sqs_queue" "dlq" {
  name                        = "${var.name}-dlq${local.suffix}"
  fifo_queue                  = var.fifo
  content_based_deduplication = var.fifo ? true : null
  message_retention_seconds   = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled     = true
}

# --- Main queue ---
resource "aws_sqs_queue" "main" {
  name                        = "${var.name}${local.suffix}"
  fifo_queue                  = var.fifo
  content_based_deduplication = var.fifo ? true : null

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  sqs_managed_sse_enabled    = true # encryption at rest, free

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# DLQ sirf is queue ke failed messages le sake
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

# --- Queue policy: TLS only ---
data "aws_iam_policy_document" "queue" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.main.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_s3_bucket_arns) > 0 ? [1] : []

    content {
      sid       = "AllowS3Send"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.main.arn]

      principals {
        type        = "Service"
        identifiers = ["s3.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = var.allowed_s3_bucket_arns
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.queue.json

  lifecycle {
    precondition {
      condition     = !(var.fifo && length(var.allowed_s3_bucket_arns) > 0)
      error_message = "S3 event notifications are not supported by FIFO queue. fifo = false"
    }
  }
}

# --- Ready-made IAM policies ---
data "aws_iam_policy_document" "producer" {
  statement {
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.main.arn]
  }
}

data "aws_iam_policy_document" "consumer" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.main.arn]
  }
}