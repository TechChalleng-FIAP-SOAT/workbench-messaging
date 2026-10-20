variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Conta AWS esperada (guard-rail). Vazio = sem restrição."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Ambiente de deploy (ex.: develop, main, local)."
  type        = string
  default     = "local"
}

variable "name_prefix" {
  description = "Prefixo dos recursos de mensageria."
  type        = string
  default     = "workbench"
}

# --- LocalStack --------------------------------------------------------------

variable "use_localstack" {
  description = "Quando true, aponta SNS/SQS/STS para o LocalStack e usa credenciais fake."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "Endpoint do LocalStack (quando use_localstack = true)."
  type        = string
  default     = "http://localhost:4566"
}

# --- Mensageria --------------------------------------------------------------

variable "max_receive_count" {
  description = "Nº de tentativas antes de a mensagem ir para a DLQ (redrive policy)."
  type        = number
  default     = 3
}

variable "message_retention_seconds" {
  description = "Retenção de mensagens nas filas (segundos). Padrão: 4 dias."
  type        = number
  default     = 345600
}

variable "visibility_timeout_seconds" {
  description = "Tempo de invisibilidade da mensagem após ser recebida (segundos)."
  type        = number
  default     = 30
}
