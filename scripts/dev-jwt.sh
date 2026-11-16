#!/usr/bin/env bash
# Assina JWTs de DESENVOLVIMENTO (RS256, kid=workbench-auth) com a chave de dev-keys/, como a
# Lambda de login faria na AWS. Uso: source scripts/dev-jwt.sh; mint_dev_jwt '<json das claims>'.
# Requer openssl. Se o par ainda não existe nesta máquina, ele é gerado agora (scripts/dev-keys.sh;
# a chave privada não vem do repositório). A chave pode ser trocada por DEV_JWT_PRIVATE_KEY
# (Base64 do DER PKCS#8); nesse caso a pública correspondente precisa estar em JWT_PUBLIC_KEY.

_dev_jwt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=dev-keys.sh
[ -n "${DEV_JWT_PRIVATE_KEY:-}" ] || source "$_dev_jwt_dir/scripts/dev-keys.sh" || return 1

_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

mint_dev_jwt() {
  local claims="$1" key_b64 pem header payload signature
  key_b64="${DEV_JWT_PRIVATE_KEY:-$(cat "$_dev_jwt_dir/dev-keys/jwt-auth-dev.key")}"
  pem="$(mktemp)"
  {
    echo "-----BEGIN PRIVATE KEY-----"
    printf '%s' "$key_b64" | fold -w 64
    echo
    echo "-----END PRIVATE KEY-----"
  } > "$pem"
  header=$(printf '{"alg":"RS256","typ":"JWT","kid":"workbench-auth"}' | _b64url)
  payload=$(printf '%s' "$claims" | _b64url)
  signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$pem" -binary | _b64url)
  rm -f "$pem"
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}
