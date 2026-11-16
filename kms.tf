# =============================================================================
# Criptografia em repouso da mensageria
#
# - Tópicos SNS: chave KMS própria (CMK). A chave gerenciada aws/sns não serve porque o
#   CloudWatch não consegue publicar os alarmes num tópico cifrado com ela. As mensagens
#   levam dado pessoal (documento e e-mail do cliente).
# - Filas SQS e DLQs: criptografia gerenciada pelo próprio SQS (SSE-SQS), sem custo e sem
#   permissão de KMS para os consumidores.
#
# Quem publica no SNS (os pods, pela role dos nós do EKS) precisa de kms:GenerateDataKey e
# kms:Decrypt nesta chave — a permissão está no workbench-k8s-terraform (via SNS).
# No LocalStack (compose) a criptografia fica desligada.
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "messaging" {
  count                   = var.use_localstack ? 0 : 1
  description             = "Criptografia dos tópicos SNS da plataforma ${var.name_prefix} (${var.environment})."
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AdministracaoPelaConta"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # SNS cifra/decifra as mensagens; CloudWatch publica os alarmes das DLQs; SES publica
        # bounces e reclamações no tópico de alertas.
        Sid       = "UsoPeloSnsCloudWatchESes"
        Effect    = "Allow"
        Principal = { Service = ["sns.amazonaws.com", "cloudwatch.amazonaws.com", "ses.amazonaws.com"] }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "messaging" {
  count         = var.use_localstack ? 0 : 1
  name          = "alias/${var.name_prefix}-messaging"
  target_key_id = aws_kms_key.messaging[0].key_id
}

locals {
  # null = sem criptografia (LocalStack).
  sns_kms_key_id = var.use_localstack ? null : aws_kms_key.messaging[0].arn
}
