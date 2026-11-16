#!/bin/sh
# OWASP ZAP API Scan da plataforma de microsserviços (Fase 4).
#
# Para cada serviço: lê a spec OpenAPI direto do container (/v3/api-docs) e ataca
# as rotas ATRAVÉS DO GATEWAY local (-O), que é o mesmo caminho de um cliente real.
# O JWT de ADMIN (RS256, 1 h) chega pronto em ZAP_TOKEN: o zap/scan-platform.sh o assina com
# a chave de dev (dev-keys/) — localmente não existe a Lambda de login.
#
# Relatórios: /zap/wrk/<serviço>/zap-report.{html,json} + zap-scan.log (= ./zap-reports no host)
# Uso: zap/scan-platform.sh (um container por serviço; ZAP_SERVICES escolhe o serviço)
set -u

# Esquema usado para chegar nos serviços e no gateway (padrão: http, rede local do compose).
SERVICE_SCHEME="${SERVICE_SCHEME:-http}"
GATEWAY_URL="${GATEWAY_URL:-${SERVICE_SCHEME}://gateway:8000}"
REPORT_DIR=/zap/wrk
cp /zap/scripts/rules.conf "$REPORT_DIR/rules.conf"
SERVICES="${ZAP_SERVICES:-os-service customer-service billing-service execution-service}"

echo "== OWASP ZAP — plataforma Workbench (alvo: $GATEWAY_URL)"

i=0
until curl -s -o /dev/null "$GATEWAY_URL/actuator/health"; do
  i=$((i + 1)); [ "$i" -ge 60 ] && { echo "ERRO: gateway não respondeu."; exit 1; }
  sleep 2
done

# Token de ADMIN (RS256) assinado pelo scan-platform.sh com a chave de dev (dev-keys/).
TOKEN="${ZAP_TOKEN:?defina ZAP_TOKEN (rode pelo zap/scan-platform.sh, que assina o token)}"

# Injeta o Bearer em toda requisição do ZAP (replacer de header).
AUTH="-config replacer.full_list(0).description=JWT_Auth \
-config replacer.full_list(0).enabled=true \
-config replacer.full_list(0).matchtype=REQ_HEADER \
-config replacer.full_list(0).matchstr=Authorization \
-config replacer.full_list(0).matchregex=false \
-config replacer.full_list(0).replacement=Bearer\ $TOKEN \
-config replacer.full_list(0).initiators="

STATUS=0
for svc in $SERVICES; do
  out="$REPORT_DIR/$svc"
  mkdir -p "$out"
  # Cada zap-api-scan.py sobe e derruba um daemon ZAP; o anterior deixa o .homelock
  # no diretório do ZAP e, sem removê-lo, o próximo daemon não sobe (o scan trava).
  rm -f "$HOME/.ZAP/.homelock" /home/zap/.ZAP/.homelock
  # O esquema vem de SERVICE_SCHEME. O padrão é http porque o scan roda dentro da rede do
  # docker compose local, onde os serviços não têm TLS (na AWS o tráfego é interno à VPC,
  # atrás do API Gateway). Com TLS no alvo, basta SERVICE_SCHEME=https.
  spec_url="${SERVICE_SCHEME}://$svc:8080/v3/api-docs"
  echo ""
  echo "== [$svc] spec $spec_url → ataques via $GATEWAY_URL"
  zap-api-scan.py \
    -t "$spec_url" \
    -f openapi \
    -O "$GATEWAY_URL" \
    -c rules.conf \
    -z "$AUTH" \
    -r "$svc/zap-report.html" \
    -J "$svc/zap-report.json" \
    > "$out/zap-scan.log" 2>&1
  rc=$?
  # zap-api-scan.py: 0 = limpo, 1 = algum FAIL (rules.conf), 2 = só WARN, 3 = erro do ZAP
  echo "   exit=$rc  $(grep -E '^FAIL-NEW' "$out/zap-scan.log" | tail -1)"
  if [ "$rc" -eq 1 ] || [ "$rc" -eq 3 ]; then STATUS=1; fi
done

echo ""
echo "== Relatórios em $REPORT_DIR/<serviço>/zap-report.html"
# Falha só com FAIL (vulnerabilidade crítica de rules.conf) ou erro do ZAP; WARN não bloqueia.
exit "$STATUS"
