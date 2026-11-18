terraform {
  # 1.11+ es requerido por `terraform test -junit-xml`, usado en el pipeline.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # El estado remoto se configura con configuración parcial para no fijar
  # nombres de bucket ni credenciales en el código:
  #   terraform init -backend-config=backend.hcl
  # Ver backend.hcl.example. Sin ese archivo, el estado queda local (solo laboratorio).
}
