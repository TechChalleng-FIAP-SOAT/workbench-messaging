# Chaves de desenvolvimento do JWT (RS256)

**Só para a máquina local** (compose, `e2e/saga-e2e.sh`, scan do ZAP). São públicas no
repositório de propósito, como era o antigo `JWT_SECRET` de dev — **nunca use na AWS**.

| Arquivo | O que é |
|---|---|
| `jwt-auth-dev.key` | Chave privada (PKCS#8, Base64 do DER) que faz o papel da Lambda de login: assina tokens com `kid=workbench-auth` |
| `jwt-auth-dev.pub` | Chave pública correspondente — é o padrão de `JWT_PUBLIC_KEY` no perfil `local` dos serviços |

O par do token de serviço do os-service (`kid=os-service`) fica no `application-local.yml` do
os-service (privada) e do customer-service (pública).

Gerar um token de dev: `source scripts/dev-jwt.sh && mint_dev_jwt '{"sub":"admin@workbench.dev","roles":["ADMIN"],"exp":4102444800}'`.
