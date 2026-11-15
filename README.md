# workbench-messaging

Infraestrutura de **mensageria assíncrona** da plataforma Workbench (Tech Challenge
Fase 4): provisiona os **tópicos SNS**, as **filas SQS** (uma por consumidor) e as
**DLQs** que sustentam a **Saga orquestrada** entre os microsserviços.

Segue o padrão dos demais repos de infra do projeto: Terraform próprio, provider
AWS `~> 5.0`, backend S3 no CI. O diferencial é ser **parametrizado para rodar no
LocalStack** (local, sem custo) ou na **AWS real**, com o mesmo código.

---

## 1. O que é / para que serve

Na Fase 4 a comunicação entre serviços deixa de ser in-process e passa a usar um
broker. Este repo cria o broker:

- **Tópicos SNS** (fan-out) — um por domínio emissor.
- **Filas SQS** — uma por serviço consumidor, inscrita nos tópicos que ele ouve.
- **DLQ** — fila morta por consumidor; mensagem que falha `max_receive_count`
  vezes (padrão 3) é desviada para lá, em vez de ficar em loop.

Isso implementa o requisito do PDF: *"Mensageria assíncrona (RabbitMQ, Kafka, SQS,
etc.) para eventos e integração desacoplada"* e dá base para o **rollback/compensação**
da Saga.

## 2. Como funciona (topologia)

```
                         ┌───────────── SNS ─────────────┐
  OS Service  ──pub──▶   │  workbench-order-events        │
                         │  workbench-billing-events      │
                         │  workbench-execution-events    │
                         └───┬───────────┬───────────┬────┘
                             │           │           │
                   (subscribe por consumidor, fan-out)
                             ▼           ▼           ▼
   workbench-billing-commands-queue   workbench-execution-commands-queue
   workbench-os-saga-replies-queue    (+ cada uma com sua -dlq)
```

- **OS Service** (orquestrador) publica comandos em `order-events`; o Billing e o
  Execution os recebem em suas filas de comando.
- **Billing** e **Execution** publicam eventos de resposta nos seus tópicos; o OS
  Service os recebe em `os-saga-replies-queue`.
- Mapeamento fila→tópicos está em `local.queues` no `main.tf`.
- **Notificação ao cliente** (fora da Saga): tópico `workbench-os-notifications`, onde o
  OS Service publica o e-mail de mudança de status e o link de pagamento. Na AWS real, se
  `notification_email` for informado, uma subscription de e-mail entrega a mensagem (o
  destinatário precisa confirmar a inscrição); no LocalStack não há entrega de e-mail.
  O ARN sai no output `notifications_topic_arn` (→ `NOTIFICATIONS_TOPIC_ARN` do os-service).

> **Contrato das mensagens (executável):** [`contracts/saga-messages.json`](contracts/saga-messages.json)
> é a fonte única — emissor, consumidor, campos obrigatórios e um exemplo de payload
> de cada mensagem. Os serviços da Saga (os, billing, execution) têm uma cópia em
> `src/test/resources/contracts/` e um **teste de contrato** (`*SagaContractTest`) que
> roda no `mvn verify` de cada um: confere os nomes do `SagaMessages`, se o que o
> serviço publica tem os campos obrigatórios e se ele aceita o exemplo que consome.
>
> Para mudar o contrato: edite o JSON aqui, rode `scripts/sync-saga-contract.sh` (copia
> para os repositórios irmãos) e ajuste os serviços até os testes passarem.
> `scripts/sync-saga-contract.sh --check` só confere se as cópias estão iguais.
>
> Explicação em texto: `workbench-technical-documentation/01 - Arquitetura/Contratos de Mensagem.md`.

## 3. Como foi feito

- `versions.tf` — provider AWS parametrizado: quando `use_localstack = true`,
  aponta SNS/SQS/STS para `http://localhost:4566` e usa credenciais fake.
- `main.tf` — `for_each` sobre `local.topics` e `local.queues`; subscriptions
  SNS→SQS com `raw_message_delivery`; `redrive_policy` para a DLQ; policy que
  autoriza só os tópicos inscritos a publicar na fila.
- `outputs.tf` — ARNs/URLs de tópicos e filas, para os serviços consumirem.

## 4. Rodar no LocalStack (recomendado p/ desenvolver)

Pré-requisitos: Docker, Terraform e AWS CLI instalados.

```bash
# sobe o LocalStack e aplica o Terraform contra ele
./bootstrap-localstack.sh

# conferir recursos
aws --endpoint-url=http://localhost:4566 sqs list-queues --region us-east-1
aws --endpoint-url=http://localhost:4566 sns list-topics --region us-east-1

# destruir
./bootstrap-localstack.sh destroy
```

Os serviços da aplicação apontam para `http://localhost:4566` em dev (mesmo
endpoint), então publicam/consomem exatamente como fariam na AWS.

## 5. Rodar na AWS real

```bash
cp terraform.tfvars.example terraform.tfvars   # preencha o perfil AWS

terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=messaging/<env>/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform apply -var "use_localstack=false" -var "environment=develop"
```

> Aplicar na AWS é **ação do usuário** (requer credenciais). Veja
> `workbench-technical-documentation/09 - Operacao/Deploy na AWS.md` (FASE 4).

**Criptografia em repouso (`kms.tf`, só na AWS real):** os tópicos SNS usam uma chave KMS
própria (`alias/workbench-messaging`, rotação anual), porque a chave gerenciada `aws/sns` não
aceita os alarmes do CloudWatch; as filas e DLQs usam a criptografia gerenciada do SQS.
Os pods publicam com a permissão de KMS da role dos nós (`workbench-k8s-terraform`).

**Alarmes das DLQs (`alarms.tf`, só na AWS real):** um alarme do CloudWatch por DLQ
(`ApproximateNumberOfMessagesVisible > 0`) avisa no tópico `workbench-alerts`. Passe
`-var "alert_email=..."` para receber por e-mail (confirme a inscrição). O que fazer quando
o alarme tocar: `workbench-technical-documentation/09 - Operacao/Runbook.md`.

## 6. Validação (sem criar nada)

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
```

## 7. Variáveis principais

| Variável | Default | Descrição |
|---|---|---|
| `use_localstack` | `false` | Alterna entre LocalStack e AWS real |
| `localstack_endpoint` | `http://localhost:4566` | Endpoint do LocalStack |
| `name_prefix` | `workbench` | Prefixo dos recursos |
| `max_receive_count` | `3` | Tentativas antes da DLQ |
| `visibility_timeout_seconds` | `30` | Invisibilidade pós-recebimento |
| `message_retention_seconds` | `345600` | Retenção (4 dias) |
| `notification_email` | `""` | (opcional) e-mail inscrito no tópico de notificação ao cliente |
