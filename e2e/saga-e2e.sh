#!/usr/bin/env bash
# Teste ponta a ponta da plataforma (gateway -> os/customer/billing/execution -> SNS/SQS no LocalStack).
#
# Pré-requisitos:
#   - plataforma no ar, com pagamento simulado (padrão do compose: PAYMENT_PROVIDER=fake):
#       docker compose -f docker-compose.dev.yml --profile app up -d --build
#   - bash, curl, jq e openssl
#
# Uso:
#   e2e/saga-e2e.sh                 # roda os 4 cenários
#   e2e/saga-e2e.sh feliz           # só alguns: feliz | estoque | pagamento | seguranca
#
# Variáveis opcionais:
#   GATEWAY_URL      (padrão: gateway local do compose, porta 8000)
#   DEV_JWT_PRIVATE_KEY  chave privada de dev (padrão: dev-keys/jwt-auth-dev.key, gerada na 1ª execução)
#   E2E_SCHEME       esquema do gateway local (padrão http; use https se houver TLS)
#   E2E_TIMEOUT      segundos de espera por cada passo assíncrono (padrão 60)
#
# Os dados criados (cliente, veículo, produto) são únicos por execução, então o teste pode rodar
# várias vezes sem limpar o banco. Sai com código 0 se tudo passou e 1 se algo falhou.
# Não usa Mercado Pago: o webhook só existe com PAYMENT_PROVIDER=fake e o teste aborta se o billing
# estiver com outro provedor.
set -uo pipefail

# O esquema vem de variável: o gateway local do compose só fala HTTP, dentro da máquina.
E2E_SCHEME="${E2E_SCHEME:-http}"
GW="${GATEWAY_URL:-${E2E_SCHEME}://localhost:8000}"
TIMEOUT="${E2E_TIMEOUT:-60}"

for bin in curl jq openssl; do
  command -v "$bin" >/dev/null || { echo "Falta o comando '$bin'." >&2; exit 2; }
done

PASS=0
FAIL=0
STATUS=""
BODY=""

# ---------- saída ----------
ok()   { PASS=$((PASS + 1)); printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✘\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
check() { # check "descrição" esperado obtido
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado: $2 | obtido: $3)"; fi
}

# ---------- JWT RS256 (como a Lambda de login: kid=workbench-auth, chave de dev-keys/) ----------
# shellcheck source=../scripts/dev-jwt.sh
source "$(dirname "$0")/../scripts/dev-jwt.sh"
mint() { mint_dev_jwt "$1"; } # mint '<json das claims>'
EXP=$(( $(date +%s) + 3600 ))
ADMIN=$(mint "{\"sub\":\"admin@workbench.dev\",\"roles\":[\"ADMIN\"],\"exp\":$EXP}")
client_token() { mint "{\"sub\":\"$1\",\"clientId\":$2,\"roles\":[\"CLIENT\"],\"exp\":$EXP}"; }

# ---------- HTTP ----------
api() { # api METODO CAMINHO TOKEN [JSON]  -> preenche STATUS e BODY
  local method="$1" path="$2" token="$3" data="${4:-}" out
  local args=(-s -w $'\n%{http_code}' -X "$method" "$GW$path" -H 'Content-Type: application/json')
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$data" ]] && args+=(-d "$data")
  out=$(curl "${args[@]}") || out=$'\n000'
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}
expect_status() { # expect_status "descrição" código   (usa o último api)
  check "$1" "$2" "$STATUS"
}
jqb() { jq -r "$1" <<<"$BODY" 2>/dev/null; }

wait_for() { # wait_for "descrição" CAMINHO TOKEN 'filtro jq' esperado
  local desc="$1" path="$2" token="$3" filter="$4" want="$5" got="" end=$((SECONDS + TIMEOUT))
  while (( SECONDS < end )); do
    api GET "$path" "$token"
    got=$(jqb "$filter")
    [[ "$got" == "$want" ]] && { ok "$desc"; return 0; }
    sleep 1
  done
  bad "$desc (esperado: $want | último valor: $got)"
  return 1
}

# ---------- dados únicos por execução ----------
gen_cpf() {
  local d=() i s r n out=""
  for i in 0 1 2 3 4 5 6 7 8; do d+=($((RANDOM % 10))); done
  for n in 10 11; do
    s=0
    for ((i = 0; i < n - 1; i++)); do s=$((s + d[i] * (n - i))); done
    r=$(( (s * 10) % 11 )); (( r == 10 )) && r=0
    d+=("$r")
  done
  for i in "${d[@]}"; do out+="$i"; done
  printf '%s' "$out"
}
LETTERS=ABCDEFGHJKLMNPRSTUVXZ
gen_plate() { # padrão Mercosul: LLLNLNN
  printf '%s%s%s%s%s%s%s' "${LETTERS:RANDOM%21:1}" "${LETTERS:RANDOM%21:1}" "${LETTERS:RANDOM%21:1}" \
    $((RANDOM % 10)) "${LETTERS:RANDOM%21:1}" $((RANDOM % 10)) $((RANDOM % 10))
}

CPF="" CID="" PLATE="" PID="" OID=""

new_client_and_vehicle() { # cria cliente + veículo; preenche CPF CID PLATE
  CPF=$(gen_cpf); PLATE=$(gen_plate)
  api POST /api/clients "$ADMIN" "{\"name\":\"E2E Teste\",\"document\":\"$CPF\",\"email\":\"e2e-$CPF@example.com\",\"phone\":\"11999990000\"}"
  expect_status "cliente criado ($CPF)" 201
  CID=$(jqb .id)
  api POST /api/vehicles "$ADMIN" "{\"clientId\":$CID,\"plate\":\"$PLATE\",\"brand\":\"VW\",\"model\":\"Gol\",\"year\":2018,\"color\":\"Prata\",\"type\":\"CAR\"}"
  expect_status "veículo criado ($PLATE)" 201
}

new_product_with_stock() { # new_product_with_stock QTD ; preenche PID
  local sku="E2E-$(date +%s)-$RANDOM"
  api POST /api/products "$ADMIN" "{\"name\":\"Oleo E2E\",\"sku\":\"$sku\",\"type\":\"PART\",\"unit\":\"UNIT\",\"category\":\"Lubrificantes\",\"brand\":\"Mobil\",\"costPrice\":25.00,\"salePrice\":45.00,\"warrantyMonths\":6,\"fractionalAllowed\":false,\"packageSize\":1}"
  expect_status "produto criado ($sku)" 201
  PID=$(jqb .id)
  api POST /api/stocks "$ADMIN" "{\"productId\":\"$PID\",\"quantity\":$1,\"minimumQuantity\":1}"
  expect_status "estoque criado ($1 un.)" 201
}

stock_field() { api GET "/api/stocks/product/$PID" "$ADMIN"; jqb ".$1"; }

open_order() { # preenche OID
  api POST /order "$ADMIN" "{\"cpfCnpj\":\"$CPF\",\"placaVeiculo\":\"$PLATE\",\"serviceTypes\":[\"TROCA_OLEO\"]}"
  expect_status "OS aberta" 201
  OID=$(jqb .id)
  check "OS nasce RECEBIDA" RECEBIDA "$(jqb .serviceStatus)"
}

diagnose() { # diagnose QTD_PECAS
  api POST "/order/$OID/diagnosis" "$ADMIN" \
    "{\"parts\":[{\"productId\":\"$PID\",\"quantity\":$1}],\"services\":[{\"serviceType\":\"TROCA_OLEO\",\"laborCost\":80.00,\"useDefault\":false}]}"
  expect_status "diagnóstico registrado (dispara a Saga)" 200
}

saga_field() { api GET "/order/$OID/saga" "$ADMIN"; jqb ".$1"; }
order_status() { api GET "/order/id/$OID" "$ADMIN"; jqb .serviceStatus; }

# Leva a OS aprovada até PAGAMENTO_PENDENTE e confirma que a cobrança foi criada (provedor fake).
# preenche GATEWAY_PAYMENT_ID
GATEWAY_PAYMENT_ID=""
approve_and_run_service() {
  local token sid
  token=$(client_token "$CPF" "$CID")
  wait_for "Saga gera o orçamento e a OS vai para AGUARDANDO_APROVACAO" "/order/id/$OID" "$ADMIN" .serviceStatus AGUARDANDO_APROVACAO || return 1
  api GET "/api/budgets/service-order/$OID" "$ADMIN"
  check "orçamento: peças 2 x 45,00 + mão de obra 80,00 = 170,00" 170.00 "$(jqb .totalPrice)"
  check "estoque: 2 unidades reservadas" 2 "$(stock_field reservedQuantity)"

  api POST "/order/$OID/decision" "$token" '{"decision":"APPROVED"}'
  expect_status "cliente aprova o orçamento" 204
  wait_for "Saga avança para AGUARDANDO_PAGAMENTO" "/order/$OID/saga" "$ADMIN" .step AGUARDANDO_PAGAMENTO || return 1
  check "OS APROVADO" APROVADO "$(order_status)"

  api PATCH "/order/$OID" "$ADMIN" '{"status":"EM_EXECUCAO"}'
  expect_status "OS vai para EM_EXECUCAO" 204
  api GET "/order/$OID/services" "$ADMIN"
  sid=$(jqb '.[0].id')
  api PATCH "/order/$OID/services/$sid/status" "$ADMIN" '{"status":"DOING"}'
  expect_status "serviço em andamento" 200
  api PATCH "/order/$OID/services/$sid/status" "$ADMIN" '{"status":"DONE"}'
  expect_status "serviço concluído" 200
  check "último serviço DONE finaliza a OS" FINALIZADA "$(order_status)"
}

request_payment() { # PATCH -> PAGAMENTO_PENDENTE e espera a cobrança
  api PATCH "/order/$OID" "$ADMIN" '{"status":"PAGAMENTO_PENDENTE"}'
  expect_status "OS vai para PAGAMENTO_PENDENTE (cobrança automática)" 204
  wait_for "billing cria a cobrança PENDENTE" "/api/payments/service-order/$OID" "$ADMIN" .status PENDENTE || return 1
  GATEWAY_PAYMENT_ID=$(jqb .gatewayPaymentId)
  if [[ "$(jqb .checkoutUrl)" != https://fake-checkout.local/* ]]; then
    bad "billing não está com PAYMENT_PROVIDER=fake (checkoutUrl: $(jqb .checkoutUrl)). Suba o compose sem PAYMENT_PROVIDER=mercadopago."
    exit 2
  fi
  ok "cobrança criada com link de checkout"
}

webhook() { # webhook ID true|false
  api POST /api/payments/webhook "$ADMIN" "{\"gatewayPaymentId\":\"$1\",\"approved\":$2}"
  expect_status "webhook do gateway ($2) aceito" 200
}

# ================= cenários =================

cenario_feliz() {
  step "Cenário 1 — caminho feliz: da OS à entrega"
  new_client_and_vehicle
  new_product_with_stock 100
  open_order
  diagnose 2
  approve_and_run_service || return
  request_payment || return
  webhook "$GATEWAY_PAYMENT_ID" true
  wait_for "OS ENTREGUE" "/order/id/$OID" "$ADMIN" .serviceStatus ENTREGUE
  wait_for "Saga CONCLUIDA" "/order/$OID/saga" "$ADMIN" .step CONCLUIDA
  check "estoque: reserva baixada (quantidade 98)" 98 "$(stock_field quantity)"
  check "estoque: nada mais reservado" 0 "$(stock_field reservedQuantity)"
  api GET "/api/payments/service-order/$OID/history" "$ADMIN"
  check "histórico do pagamento: PENDENTE → PAGAMENTO_APROVADO" "PENDENTE,PAGAMENTO_APROVADO" "$(jqb '[.[].status] | join(",")')"
}

cenario_estoque() {
  step "Cenário 2 — compensação: estoque insuficiente no diagnóstico"
  new_client_and_vehicle
  new_product_with_stock 1
  open_order
  diagnose 5
  wait_for "Saga vai para FALHOU" "/order/$OID/saga" "$ADMIN" .step FALHOU || return
  [[ -n "$(saga_field failureReason | grep -v '^null$')" ]] && ok "Saga informa o motivo da falha" || bad "Saga sem motivo da falha"
  check "OS permanece em EM_DIAGNOSTICO" EM_DIAGNOSTICO "$(order_status)"
  check "nada ficou reservado" 0 "$(stock_field reservedQuantity)"
  diagnose 1
  wait_for "novo diagnóstico recomeça a Saga (AGUARDANDO_APROVACAO)" "/order/id/$OID" "$ADMIN" .serviceStatus AGUARDANDO_APROVACAO
  check "reserva refeita (1 unidade)" 1 "$(stock_field reservedQuantity)"
}

cenario_pagamento() {
  step "Cenário 3 — pagamento recusado e nova cobrança"
  new_client_and_vehicle
  new_product_with_stock 100
  open_order
  diagnose 2
  approve_and_run_service || return
  request_payment || return
  local first="$GATEWAY_PAYMENT_ID"
  webhook "$first" false
  wait_for "Saga registra a recusa" "/order/$OID/saga" "$ADMIN" .failureReason "pagamento recusado pelo gateway" || return
  check "OS permanece em PAGAMENTO_PENDENTE" PAGAMENTO_PENDENTE "$(order_status)"
  check "Saga continua em AGUARDANDO_PAGAMENTO" AGUARDANDO_PAGAMENTO "$(saga_field step)"

  api POST "/order/$OID/payment-retry" "$(client_token "$CPF" "$CID")"
  expect_status "cliente pede nova cobrança" 202
  wait_for "recusa anterior é limpa" "/order/$OID/saga" "$ADMIN" .failureReason null || return
  # A recusa é limpa na hora, mas a nova cobrança chega pela fila do billing (polling de alguns
  # segundos): espera o id mudar em vez de ler uma vez só.
  local second="" deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    api GET "/api/payments/service-order/$OID" "$ADMIN"
    second=$(jqb .gatewayPaymentId)
    [[ -n "$second" && "$second" != "null" && "$second" != "$first" ]] && break
    sleep 2
  done
  [[ -n "$second" && "$second" != "null" && "$second" != "$first" ]] && ok "nova cobrança com outro id" || bad "nova cobrança não foi criada (id: $second)"
  webhook "$second" true
  wait_for "OS ENTREGUE após o segundo pagamento" "/order/id/$OID" "$ADMIN" .serviceStatus ENTREGUE
  api GET "/api/payments/service-order/$OID/history" "$ADMIN"
  check "histórico: PENDENTE, RECUSADO, PENDENTE, PAGAMENTO_APROVADO" \
    "PENDENTE,RECUSADO,PENDENTE,PAGAMENTO_APROVADO" "$(jqb '[.[].status] | join(",")')"
}

cenario_seguranca() {
  step "Cenário 4 — autenticação e posse dos dados"
  new_client_and_vehicle
  local cpf_a="$CPF" cid_a="$CID"
  new_product_with_stock 10
  open_order
  local other_cpf other_cid
  CPF=$(gen_cpf)
  api POST /api/clients "$ADMIN" "{\"name\":\"Outro Cliente\",\"document\":\"$CPF\",\"email\":\"outro-$CPF@example.com\",\"phone\":\"11988880000\"}"
  expect_status "segundo cliente criado" 201
  other_cpf="$CPF"; other_cid=$(jqb .id)
  local tok_b; tok_b=$(client_token "$other_cpf" "$other_cid")

  api GET "/order/id/$OID" ""
  expect_status "sem token: 401" 401
  api GET "/order/id/$OID" "invalido.token.aqui"
  expect_status "token inválido: 401" 401
  api PATCH "/order/$OID" "$tok_b" '{"status":"EM_EXECUCAO"}'
  expect_status "cliente não altera status da OS (rota de staff): 403" 403
  api GET "/order/document/$cpf_a" "$tok_b"
  expect_status "cliente B não consulta as OS do cliente A: 403" 403
  api GET "/order/document/$cpf_a" "$(client_token "$cpf_a" "$cid_a")"
  expect_status "cliente A consulta as próprias OS: 200" 200
  api POST "/order/$OID/decision" "$tok_b" '{"decision":"APPROVED"}'
  check "cliente B não decide o orçamento da OS do cliente A (403 ou 404)" "true" \
    "$([[ "$STATUS" == 403 || "$STATUS" == 404 ]] && echo true || echo "false (HTTP $STATUS)")"
}

# ================= execução =================

step "Pré-checagem"
api GET /actuator/health ""
if [[ "$STATUS" != "200" ]]; then
  echo "Gateway/os-service não responde em $GW (HTTP $STATUS). Suba a plataforma:" >&2
  echo "  docker compose -f docker-compose.dev.yml --profile app up -d --build" >&2
  exit 2
fi
ok "plataforma respondendo em $GW"

wanted=("$@")
[[ ${#wanted[@]} -eq 0 ]] && wanted=(feliz estoque pagamento seguranca)
for name in "${wanted[@]}"; do
  case "$name" in
    feliz)     cenario_feliz ;;
    estoque)   cenario_estoque ;;
    pagamento) cenario_pagamento ;;
    seguranca) cenario_seguranca ;;
    *) echo "Cenário desconhecido: $name (use feliz | estoque | pagamento | seguranca)" >&2; exit 2 ;;
  esac
done

printf '\n\033[1mResultado: %d passou, %d falhou\033[0m\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
