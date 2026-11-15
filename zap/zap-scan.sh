#!/bin/sh
# OWASP ZAP API Scan da plataforma de microsserviços (Fase 4).
#
# Para cada serviço: lê a spec OpenAPI direto do container (/v3/api-docs) e ataca
# as rotas ATRAVÉS DO GATEWAY local (-O), que é o mesmo caminho de um cliente real.
# O JWT de ADMIN é assinado aqui mesmo com o JWT_SECRET de dev (HS256, 1 h) —
# localmente não existe a Lambda de login, e assim nenhum token fica fixo no repo.
#
# Relatórios: /zap/wrk/<serviço>/zap-report.{html,json} + zap-scan.log (= ./zap-reports no host)
# Uso: zap/scan-platform.sh (um container por serviço; ZAP_SERVICES escolhe o serviço)
set -u

GATEWAY_URL="${GATEWAY_URL:-http://gateway:8000}"
REPORT_DIR=/zap/wrk
cp /zap/scripts/rules.conf "$REPORT_DIR/rules.conf"
SERVICES="${ZAP_SERVICES:-os-service customer-service billing-service execution-service}"

echo "== OWASP ZAP — plataforma Workbench (alvo: $GATEWAY_URL)"

i=0
until curl -s -o /dev/null "$GATEWAY_URL/actuator/health"; do
  i=$((i + 1)); [ "$i" -ge 60 ] && { echo "ERRO: gateway não respondeu."; exit 1; }
  sleep 2
done

TOKEN=$(python3 - <<'PY'
import base64, hashlib, hmac, json, os, time
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
secret = os.environ.get("JWT_SECRET", "akmsdkmasfnjsgknakmsdkmasdkmsadfkmdsakmdkmsadsa").encode()
now = int(time.time())
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
body = b64(json.dumps({"sub": "admin@workbench.dev", "roles": ["ADMIN"], "iat": now, "exp": now + 3600}).encode())
sig = b64(hmac.new(secret, f"{head}.{body}".encode(), hashlib.sha256).digest())
print(f"{head}.{body}.{sig}")
PY
)

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
  echo ""
  echo "== [$svc] spec http://$svc:8080/v3/api-docs → ataques via $GATEWAY_URL"
  zap-api-scan.py \
    -t "http://$svc:8080/v3/api-docs" \
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
