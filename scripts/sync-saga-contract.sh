#!/usr/bin/env bash
# Copia o contrato da Saga (fonte única: contracts/saga-messages.json) para os
# serviços que participam dela, onde o teste de contrato de cada um o lê.
#
#   scripts/sync-saga-contract.sh          # copia para os repositórios irmãos
#   scripts/sync-saga-contract.sh --check  # só confere se as cópias estão iguais (exit 1 se não)
#
# Supõe os repositórios lado a lado (mesma pasta pai), como no workspace do grupo.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
source_file="$here/contracts/saga-messages.json"
target="src/test/resources/contracts/saga-messages.json"
services=(workbench-os-service workbench-billing-service workbench-execution-service)

status=0
for svc in "${services[@]}"; do
  dest="$here/../$svc/$target"
  if [[ "${1:-}" == "--check" ]]; then
    if ! cmp -s "$source_file" "$dest"; then
      echo "DESATUALIZADO: $svc/$target"
      status=1
    else
      echo "ok: $svc"
    fi
  else
    mkdir -p "$(dirname "$dest")"
    cp "$source_file" "$dest"
    echo "copiado: $svc/$target"
  fi
done
exit $status
