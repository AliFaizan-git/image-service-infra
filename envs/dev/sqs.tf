# SQS is not part of the main infra yet (enable_sqs = false by default).
# So nothing gets created unless you explicitly turn it on.
#
# Checklist to enable it properly:
#
# 1. In terraform.tfvars set:
#    enable_sqs = true
#
# 2. Producer (Lambda) wiring:
#    Go to modules/lambda and add a new variable:
#    variable "extra_policy_jsons" { type = list(string), default = [] }
#    Then inside data "aws_iam_policy_document" "access" add:
#    source_policy_documents = var.extra_policy_jsons
#    After that, in lambda.tf pass the policy from SQS module:
#    extra_policy_jsons = [module.sqs[0].producer_policy_json]
#    And set the env var:
#    QUEUE_URL = module.sqs[0].queue_url
#
# 3. Consumer (backend) wiring:
#    In compute.tf, inside data "backend_task" add:
#    source_policy_documents = var.enable_sqs ? [module.sqs[0].consumer_policy_json] : []
#    And inject SQS_QUEUE_URL in backend's environment only when enabled.
#
# 4. App code:
#    Make sure NOTIFY_MODE  is set to use the sqs path.
#
# 5. If you want S3 -> SQS direct:
#    allowed_s3_bucket_arns = [module.s3_images.bucket_arn]
#    Note: this only works with Standard queues. S3 events can't go to FIFO.

module "sqs" {
  count  = var.enable_sqs ? 1 : 0
  source = "../../modules/sqs"

  name = "${local.name_prefix}-image-events"

  # fifo                       = false
  # visibility_timeout_seconds = 120
  # max_receive_count          = 5
  # allowed_s3_bucket_arns     = [module.s3_images.bucket_arn]
}

output "sqs_queue_url" {
  description = "null jab SQS disabled ho"
  value       = one(module.sqs[*].queue_url)
}