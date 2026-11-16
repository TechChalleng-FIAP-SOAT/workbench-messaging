#!/usr/bin/env bash
# Gera o par de chaves RSA de DESENVOLVIMENTO do JWT (RS256), uma vez por máquina.
#
# A chave privada nunca vai para o repositório: dev-keys/ e .env estão no .gitignore. Cada
# máquina tem o seu par, como a Lambda de login tem o dela na AWS.
#
# Gera:
#   dev-keys/jwt-auth-dev.key  chave privada (PKCS#8, Base64 do DER, numa linha): assina os tokens
#                              de dev (kid=workbench-auth) em scripts/dev-jwt.sh
#   dev-keys/jwt-auth-dev.pub  chave pública correspondente (X.509, Base64 do DER, numa linha)
#   .env                       JWT_PUBLIC_KEY=<pública>: o docker compose lê este arquivo e passa a
#                              chave aos 4 serviços. Só é (re)escrita a linha JWT_PUBLIC_KEY.
#
# Uso:
#   scripts/dev-keys.sh           # cria o que faltar; não troca um par que já existe
#   scripts/dev-keys.sh --force   # gera um par novo (depois, suba o compose de novo: --force-recreate)
#   source scripts/dev-keys.sh    # também exporta JWT_PUBLIC_KEY para rodar um serviço pela IDE
#
# Requer openssl. Nunca use estas chaves na AWS.
_dk_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_dk_keys="$_dk_dir/dev-keys"
_dk_key="$_dk_keys/jwt-auth-dev.key"
_dk_pub="$_dk_keys/jwt-auth-dev.pub"
_dk_env="$_dk_dir/.env"

dev_keys_generate() {
  local tmp
  command -v openssl >/dev/null || { echo "dev-keys: falta o openssl." >&2; return 1; }
  mkdir -p "$_dk_keys"
  tmp="$(mktemp -d)" || return 1
  # genrsa + pkcs8 -topk8: o LibreSSL do macOS gera PKCS#1 em "genpkey -outform DER", e os serviços leem PKCS#8.
  openssl genrsa -out "$tmp/k.pem" 2048 2>/dev/null &&
    openssl pkcs8 -topk8 -nocrypt -in "$tmp/k.pem" -outform DER -out "$tmp/k8.der" &&
    openssl base64 -A -in "$tmp/k8.der" > "$_dk_key" &&
    openssl pkey -in "$tmp/k.pem" -pubout -outform DER | openssl base64 -A > "$_dk_pub" || {
      rm -rf "$tmp"; echo "dev-keys: falha ao gerar as chaves." >&2; return 1; }
  rm -rf "$tmp"
  chmod 600 "$_dk_key"
  echo "dev-keys: par novo gerado em dev-keys/ (fora do git)." >&2
}

dev_keys_write_env() {
  local pub tmp
  pub="$(cat "$_dk_pub")"
  tmp="$(mktemp)" || return 1
  { [ -f "$_dk_env" ] && grep -v '^JWT_PUBLIC_KEY=' "$_dk_env"; printf 'JWT_PUBLIC_KEY=%s\n' "$pub"; } > "$tmp" &&
    cat "$tmp" > "$_dk_env"
  rm -f "$tmp"
}

dev_keys_ensure() {
  if [ "${1:-}" = "--force" ] || [ ! -s "$_dk_key" ] || [ ! -s "$_dk_pub" ]; then
    dev_keys_generate || return 1
  fi
  dev_keys_write_env || return 1
  export JWT_PUBLIC_KEY="$(cat "$_dk_pub")"
}

# Executado direto: aceita --force. Com "source" (dev-jwt.sh, e2e, ZAP): só garante o par, sem
# olhar os argumentos do script que fez o source.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  dev_keys_ensure "${1:-}"
else
  dev_keys_ensure
fi
