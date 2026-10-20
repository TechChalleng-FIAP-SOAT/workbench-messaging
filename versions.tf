terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend S3 para develop/main (configurado pelo CI via -backend-config).
  # Para LocalStack/validação local use: terraform init -backend=false
  backend "s3" {}
}

# -----------------------------------------------------------------------------
# Provider AWS — parametrizado para funcionar tanto na AWS real quanto no
# LocalStack. Quando var.use_localstack = true, apontamos SNS/SQS/STS para o
# endpoint local e desabilitamos as validações de credencial/conta (o LocalStack
# aceita credenciais fake).
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # Guard-rail de conta só na AWS real.
  allowed_account_ids = (!var.use_localstack && var.aws_account_id != "") ? [var.aws_account_id] : []

  # Credenciais fake e validações puladas no modo LocalStack.
  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  skip_metadata_api_check     = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      sns = var.localstack_endpoint
      sqs = var.localstack_endpoint
      sts = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Project     = "workbench"
      Component   = "messaging"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
