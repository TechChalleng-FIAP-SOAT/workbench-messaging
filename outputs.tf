output "topic_arns" {
  description = "ARNs dos tópicos SNS por domínio emissor."
  value       = { for k, t in aws_sns_topic.this : k => t.arn }
}

output "queue_urls" {
  description = "URLs das filas SQS por consumidor."
  value       = { for k, q in aws_sqs_queue.this : k => q.id }
}

output "queue_arns" {
  description = "ARNs das filas SQS por consumidor."
  value       = { for k, q in aws_sqs_queue.this : k => q.arn }
}

output "dlq_urls" {
  description = "URLs das Dead-Letter Queues."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.id }
}
