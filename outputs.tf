output "topic_arns" {
  description = "ARNs dos tópicos SNS por domínio emissor."
  value       = { for k, t in aws_sns_topic.this : k => t.arn }
}

output "notifications_topic_arn" {
  description = "ARN do tópico de notificações de status ao cliente (NOTIFICATIONS_TOPIC_ARN do OS Service)."
  value       = aws_sns_topic.notifications.arn
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

output "alerts_topic_arn" {
  description = "ARN do tópico que recebe os alarmes das DLQs (vazio no LocalStack)."
  value       = var.use_localstack ? "" : aws_sns_topic.alerts[0].arn
}

output "ses_sender_email" {
  description = "Remetente verificado no SES (SES_SENDER_EMAIL do OS Service). Vazio = SES não configurado."
  value       = local.ses_enabled ? aws_sesv2_email_identity.sender[0].email_identity : ""
}

output "ses_configuration_set" {
  description = "Configuration set do SES (SES_CONFIGURATION_SET do os-service); vazio sem SES."
  value       = local.ses_enabled ? aws_sesv2_configuration_set.customer_email[0].configuration_set_name : ""
}

output "ses_dkim_records" {
  description = "CNAMEs de DKIM a publicar no DNS do ses_domain (nome -> valor)."
  value = (local.ses_enabled && var.ses_domain != "") ? {
    for token in aws_sesv2_email_identity.domain[0].dkim_signing_attributes[0].tokens :
    "${token}._domainkey.${var.ses_domain}" => "${token}.dkim.amazonses.com"
  } : {}
}
