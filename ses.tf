# =============================================================================
# E-mail ao cliente pelo Amazon SES
#
# O os-service envia o e-mail direto ao endereço do cliente (notification-channel=ses), no
# lugar do tópico SNS, cuja única assinatura recebia tudo. Aqui ficam as identidades que o
# SES exige:
#   - o REMETENTE (ses_sender_email), usado em SES_SENDER_EMAIL;
#   - em SANDBOX, também cada DESTINATÁRIO (ses_verified_recipients).
#
# Cada identidade manda um e-mail de verificação da AWS, e o dono precisa clicar no link. Sem
# isso o envio é recusado.
#
# SAIR DO SANDBOX (mandar a QUALQUER cliente): a conta nova nasce em sandbox e o acesso à
# produção é um pedido que a AWS analisa (fora do Terraform) — scripts/ses-request-production.sh.
# A AWS exige que bounces e reclamações sejam tratados: o configuration set abaixo os envia ao
# tópico de alertas. Com domínio próprio (ses_domain), a identidade de domínio com DKIM melhora
# a entrega e permite qualquer remetente @domínio.
#
# Desligado no LocalStack e quando ses_sender_email é vazio.
# =============================================================================
locals {
  ses_enabled = !var.use_localstack && var.ses_sender_email != ""
}

resource "aws_sesv2_email_identity" "sender" {
  count          = local.ses_enabled ? 1 : 0
  email_identity = var.ses_sender_email
}

resource "aws_sesv2_email_identity" "recipient" {
  for_each       = local.ses_enabled ? toset(var.ses_verified_recipients) : toset([])
  email_identity = each.value
}

# Identidade de DOMÍNIO (opcional), com DKIM: publique os 3 CNAMEs do output ses_dkim_records
# no DNS do domínio. Melhor entrega e o pedido de produção costuma ser aprovado mais rápido.
resource "aws_sesv2_email_identity" "domain" {
  count          = (local.ses_enabled && var.ses_domain != "") ? 1 : 0
  email_identity = var.ses_domain
}

# Bounces e reclamações vão para o tópico de alertas (o mesmo das DLQs): a AWS exige esse
# tratamento para liberar a produção, e um endereço que volta deve ser corrigido no cadastro.
resource "aws_sesv2_configuration_set" "customer_email" {
  count                  = local.ses_enabled ? 1 : 0
  configuration_set_name = "${var.name_prefix}-customer-email"

  reputation_options {
    reputation_metrics_enabled = true
  }
}

resource "aws_sesv2_configuration_set_event_destination" "bounces" {
  count                  = local.ses_enabled ? 1 : 0
  configuration_set_name = aws_sesv2_configuration_set.customer_email[0].configuration_set_name
  event_destination_name = "bounces-e-reclamacoes"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE", "COMPLAINT", "REJECT"]
    sns_destination {
      topic_arn = aws_sns_topic.alerts[0].arn
    }
  }
}
