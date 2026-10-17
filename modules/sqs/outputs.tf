output "queue_url" {
  value = aws_sqs_queue.main.id # in SQS id = URL
}

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}

output "queue_name" {
  value = aws_sqs_queue.main.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "producer_policy_json" {
  value = data.aws_iam_policy_document.producer.json
}

output "consumer_policy_json" {
  value = data.aws_iam_policy_document.consumer.json
}