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

# --- Notificação ao cliente (paridade com o monólito) ------------------------

variable "notification_email" {
  description = "E-mail inscrito no tópico de notificações de status da OS (confirmar a subscription no e-mail). Vazio = cria só o tópico, sem subscription."
  type        = string
  default     = ""
}

# --- Alertas -----------------------------------------------------------------

variable "alert_email" {
  description = "E-mail que recebe os alarmes das DLQs (confirmar a subscription no e-mail). Vazio = cria o tópico de alertas sem inscrito."
  type        = string
  default     = ""
}

# --- E-mail ao cliente (Amazon SES) --------------------------------------------
variable "ses_sender_email" {
  description = "Remetente dos e-mails ao cliente, verificado no SES (a AWS envia um e-mail de verificação). Vazio = não cria identidade; o os-service segue no canal SNS."
  type        = string
  default     = ""
}

variable "ses_verified_recipients" {
  description = "Destinatários a verificar no SES. Só necessário em SANDBOX, onde o SES recusa e-mail para endereço não verificado."
  type        = list(string)
  default     = []
}

variable "ses_domain" {
  description = "Domínio próprio para o SES (identidade de domínio com DKIM). Vazio = só as identidades de e-mail."
  type        = string
  default     = ""
}
