#!/usr/bin/env bash
# Pede à AWS a saída do SANDBOX do SES (para enviar e-mail a qualquer cliente, não só a
# endereços verificados). É um pedido que a AWS analisa manualmente (em geral até 24 h) e muda
# uma configuração da CONTA — rode você, conscientemente, na conta e região certas.
#
# Uso: scripts/ses-request-production.sh <url-do-projeto> [<e-mail-de-contato>]
#   ex.: scripts/ses-request-production.sh https://github.com/TechChalleng-FIAP-SOAT
# Depois: aws sesv2 get-account --region "$AWS_REGION" --query '{producao:ProductionAccessEnabled,revisao:Details.ReviewDetails}'
set -euo pipefail

WEBSITE_URL="${1:?informe a URL do projeto (ex.: o GitHub da organização)}"
CONTACT="${2:-}"
REGION="${AWS_REGION:-us-east-1}"

USE_CASE="E-mails transacionais de uma oficina mecânica (projeto acadêmico FIAP): avisos de \
mudança de status da ordem de serviço, link de pagamento e aviso de pagamento recusado, enviados \
apenas ao cliente dono da ordem, que se cadastrou com o próprio e-mail. Não há e-mail de \
marketing nem lista comprada. Bounces, reclamações e rejeições são enviados por um \
configuration set para um tópico SNS monitorado pela equipe, e o endereço com problema é \
corrigido no cadastro do cliente. Volume esperado: poucas dezenas de e-mails por dia."

args=(--production-access-enabled --mail-type TRANSACTIONAL --website-url "$WEBSITE_URL"
      --use-case-description "$USE_CASE" --contact-language PT --region "$REGION")
[[ -n "$CONTACT" ]] && args+=(--additional-contact-email-addresses "$CONTACT")

echo "Conta: $(aws sts get-caller-identity --query Account --output text) | região: $REGION"
read -r -p "Enviar o pedido de acesso à produção do SES? [s/N] " answer
[[ "$answer" == "s" || "$answer" == "S" ]] || { echo "Cancelado."; exit 1; }
aws sesv2 put-account-details "${args[@]}"
echo "Pedido enviado. Acompanhe com: aws sesv2 get-account --region $REGION"
