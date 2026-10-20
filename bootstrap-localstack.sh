#!/usr/bin/env bash
# =============================================================================
# Sobe o LocalStack e aplica o Terraform de mensageria contra ele.
# Uso:
#   ./bootstrap-localstack.sh          # sobe + apply
#   ./bootstrap-localstack.sh destroy  # destrói os recursos no LocalStack
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

echo ">> Subindo LocalStack (docker compose)..."
docker compose up -d

echo ">> Aguardando o LocalStack ficar saudável..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:4566/_localstack/health >/dev/null 2>&1; then
    echo "   LocalStack pronto."
    break
  fi
  sleep 2
done

# Override de backend para LocalStack: usa estado LOCAL em vez do S3 declarado
# em versions.tf. O arquivo é temporário e ignorado pelo .gitignore.
echo ">> gerando backend_override.tf (estado local)..."
cat > backend_override.tf <<'EOF'
# Gerado por bootstrap-localstack.sh — NÃO commitar. Sobrescreve o backend S3
# por um backend local, para desenvolvimento com LocalStack.
terraform {
  backend "local" {}
}
EOF

echo ">> terraform init (backend local)..."
terraform init -reconfigure -input=false

VARS=(-var "use_localstack=true" -var "environment=local")

if [ "${1:-}" = "destroy" ]; then
  echo ">> terraform destroy (LocalStack)..."
  terraform destroy -auto-approve "${VARS[@]}"
  exit 0
fi

echo ">> terraform apply (LocalStack)..."
terraform apply -auto-approve "${VARS[@]}"

echo ""
echo ">> Recursos criados. Listando filas e tópicos no LocalStack:"
aws --endpoint-url=http://localhost:4566 sqs list-queues --region us-east-1 || true
aws --endpoint-url=http://localhost:4566 sns list-topics --region us-east-1 || true
