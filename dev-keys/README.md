# Chaves de desenvolvimento do JWT (RS256)

**Geradas por máquina e fora do git.** Os arquivos `*.key` e `*.pub` desta pasta e o `.env` da raiz
estão no `.gitignore`: a chave privada assina token de ADMIN aceito pelos serviços locais, então
ela nunca é versionada. **Nunca use estas chaves na AWS** (lá a Lambda de login tem o par dela).

| Arquivo | O que é |
|---|---|
| `jwt-auth-dev.key` | Chave privada (PKCS#8, Base64 do DER) que faz o papel da Lambda de login: assina tokens com `kid=workbench-auth` |
| `jwt-auth-dev.pub` | Chave pública correspondente; vai para o `.env` como `JWT_PUBLIC_KEY` e o compose a entrega aos 4 serviços |

## Como criar
```bash
scripts/dev-keys.sh           # gera o par e o .env (não troca um par que já existe)
scripts/dev-keys.sh --force   # par novo; depois: docker compose ... up -d --force-recreate
```
Não precisa rodar à mão na maioria dos casos: `scripts/dev-jwt.sh`, o `e2e/saga-e2e.sh` e o
`zap/scan-platform.sh` criam o par se ele não existir. Já o `docker compose` **não** cria: sem o
`.env` ele para e pede para rodar `scripts/dev-keys.sh`.

Para rodar um serviço pela IDE ou pelo Maven, exporte a pública no mesmo terminal:
`source scripts/dev-keys.sh` (define `JWT_PUBLIC_KEY`) e depois `./mvnw spring-boot:run -Dspring-boot.run.profiles=local`.

## Gerar um token de dev
```bash
source scripts/dev-jwt.sh && mint_dev_jwt '{"sub":"admin@workbench.dev","roles":["ADMIN"],"exp":4102444800}'
```
Trocar o par invalida os tokens antigos (os serviços só aceitam a chave pública atual).

O par do token de serviço (`kid=os-service`) é outro: fica no `application-local.yml` do os-service
(privada) e do customer-service (pública) e vale só para a chamada entre esses dois.
