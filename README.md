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

> Os contratos de mensagem (payloads e compensações) estão em
> `workbench-technical-documentation/01 - Arquitetura/Contratos de Mensagem.md`.

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

> Aplicar na AWS é **ação do usuário** (requer credenciais). Veja `PENDENCIAS.md`
> na raiz do workspace.

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
