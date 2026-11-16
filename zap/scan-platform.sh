#!/usr/bin/env bash
# Scan DAST (OWASP ZAP) de todos os microsserviços, um container ZAP por serviço.
# (Vários zap-api-scan.py no mesmo container falham de forma intermitente ao subir o
#  segundo daemon; um container novo por serviço é o jeito confiável.)
#
# Pré-requisito: plataforma no ar
#   docker compose -f docker-compose.dev.yml --profile app up -d --build
# Uso:
#   zap/scan-platform.sh                      # os 4 serviços
#   zap/scan-platform.sh billing-service      # só alguns
# Relatórios: zap-reports/<serviço>/zap-report.html
set -uo pipefail
cd "$(dirname "$0")/.."

services=("$@")
[[ ${#services[@]} -eq 0 ]] && services=(os-service customer-service billing-service execution-service)

# Token de ADMIN (RS256, 1 h) assinado aqui, com a chave de dev: localmente não há a Lambda
# de login, e assim nenhum token fica fixo no repositório.
source scripts/dev-jwt.sh
ZAP_TOKEN=$(mint_dev_jwt "{\"sub\":\"admin@workbench.dev\",\"roles\":[\"ADMIN\"],\"exp\":$(( $(date +%s) + 3600 ))}")

status=0
for svc in "${services[@]}"; do
  docker compose -f docker-compose.dev.yml --profile app --profile scan \
    run --rm -e ZAP_SERVICES="$svc" -e ZAP_TOKEN="$ZAP_TOKEN" zap < /dev/null || status=1
done
echo ""
echo "Resumo:"
for svc in "${services[@]}"; do
  printf '  %-18s %s\n' "$svc" "$(grep -E '^FAIL-NEW' "zap-reports/$svc/zap-scan.log" 2>/dev/null | tail -1 || echo 'sem relatório')"
done
exit $status
