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
# isso o envio é recusado. Para mandar a QUALQUER cliente, peça acesso à produção ao SES
# (solicitação manual na AWS, fora do Terraform): a conta nova nasce em sandbox.
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
