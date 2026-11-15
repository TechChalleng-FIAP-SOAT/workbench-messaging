# =============================================================================
# Alarmes das DLQs
#
# Mensagem na DLQ = um passo da Saga desistiu depois de max_receive_count tentativas
# (OS parada até alguém reprocessar). Sem alarme, isso só aparece quando o cliente
# reclama. Um alarme do CloudWatch por DLQ dispara com a 1ª mensagem visível e avisa
# no tópico de alertas (e-mail opcional). Só na AWS real: o LocalStack do compose não
# emula o CloudWatch.
# =============================================================================

locals {
  alarm_queues = var.use_localstack ? {} : local.queues
}

resource "aws_sns_topic" "alerts" {
  count             = var.use_localstack ? 0 : 1
  name              = "${var.name_prefix}-alerts"
  kms_master_key_id = local.sns_kms_key_id
}

# O destinatário precisa confirmar a inscrição no e-mail recebido.
resource "aws_sns_topic_subscription" "alerts_email" {
  count     = (!var.use_localstack && var.alert_email != "") ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  for_each = local.alarm_queues

  alarm_name        = "${each.value.name}-dlq-not-empty"
  alarm_description = "Há mensagens na DLQ ${each.value.name}-dlq: um passo da Saga falhou ${var.max_receive_count} vezes. Veja o runbook: workbench-technical-documentation/09 - Operacao/Runbook.md."
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  # Sem dado (fila vazia por muito tempo) é estado normal.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]
}
