# =============================================================================
# workbench-messaging — SNS (tópicos) + SQS (filas por consumidor) + DLQ
#
# Modelo: Saga ORQUESTRADA pelo OS Service.
#   - Cada serviço emissor tem um TÓPICO SNS (fan-out).
#   - Cada serviço consumidor tem uma FILA SQS inscrita nos tópicos que consome.
#   - Cada fila tem uma DLQ (redrive após max_receive_count tentativas).
#
# Nomes seguem o doc de convenções (Arquitetura): workbench-<dominio>-events e
# workbench-<servico>-<proposito>-queue.
# =============================================================================

locals {
  # Tópicos SNS por domínio emissor.
  topics = {
    order     = "${var.name_prefix}-order-events"
    billing   = "${var.name_prefix}-billing-events"
    execution = "${var.name_prefix}-execution-events"
  }

  # Filas SQS por consumidor e os tópicos a que cada uma se inscreve.
  # - os_saga_replies: OS Service recebe os eventos de resposta da Saga.
  # - billing_commands: Billing recebe comandos do orquestrador (OS).
  # - execution_commands: Execution recebe comandos do orquestrador (OS).
  queues = {
    os_saga_replies = {
      name         = "${var.name_prefix}-os-saga-replies-queue"
      subscribe_to = ["billing", "execution"]
    }
    billing_commands = {
      name         = "${var.name_prefix}-billing-commands-queue"
      subscribe_to = ["order"]
    }
    execution_commands = {
      name         = "${var.name_prefix}-execution-commands-queue"
      subscribe_to = ["order"]
    }
  }

  # Pares (fila, tópico) achatados para criar as subscriptions com for_each.
  subscriptions = merge([
    for qkey, q in local.queues : {
      for topic in q.subscribe_to : "${qkey}__${topic}" => {
        queue_key = qkey
        topic_key = topic
      }
    }
  ]...)
}

# ----------------------------------------------------------------------------
# Tópicos SNS
# ----------------------------------------------------------------------------
resource "aws_sns_topic" "this" {
  for_each = local.topics
  name     = each.value
}

# ----------------------------------------------------------------------------
# DLQs (uma por fila principal)
# ----------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  for_each                  = local.queues
  name                      = "${each.value.name}-dlq"
  message_retention_seconds = var.message_retention_seconds
}

# ----------------------------------------------------------------------------
# Filas principais, com redrive para a DLQ
# ----------------------------------------------------------------------------
resource "aws_sqs_queue" "this" {
  for_each                   = local.queues
  name                       = each.value.name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

# ----------------------------------------------------------------------------
# Subscriptions SNS -> SQS (com raw message delivery para o payload chegar limpo)
# ----------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "this" {
  for_each             = local.subscriptions
  topic_arn            = aws_sns_topic.this[each.value.topic_key].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this[each.value.queue_key].arn
  raw_message_delivery = true
}

# ----------------------------------------------------------------------------
# Policy: permite que cada tópico inscrito envie mensagens para a fila
# ----------------------------------------------------------------------------
resource "aws_sqs_queue_policy" "allow_sns" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.this[each.key].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              for topic in each.value.subscribe_to : aws_sns_topic.this[topic].arn
            ]
          }
        }
      }
    ]
  })
}
