# Pruebas de validación de entradas (RT-03): entradas inválidas deben rechazarse
# antes de crear cualquier recurso.

mock_provider "aws" {
  source = "./tests/mocks"
}

mock_provider "random" {}

run "rt03_rechaza_ambiente_invalido" {
  command = plan

  variables {
    environment = "produccion"
  }

  expect_failures = [var.environment]
}

run "rt03_rechaza_correo_invalido" {
  command = plan

  variables {
    alarm_email = "no-es-un-correo"
  }

  expect_failures = [var.alarm_email]
}

run "rt03_rs04_rechaza_cidr_invalido" {
  command = plan

  variables {
    allowed_http_cidrs = ["999.1.1.0/24"]
  }

  expect_failures = [var.allowed_http_cidrs]
}

run "rt03_rnf04_rechaza_instancia_costosa" {
  command = plan

  variables {
    instance_type = "m5.4xlarge"
  }

  expect_failures = [var.instance_type]
}

run "rt03_rnf05_rechaza_retencion_no_soportada" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "rt03_rs09_rechaza_repositorio_no_https" {
  command = plan

  variables {
    repository_url = "git@github.com:equipo/bomberos-iac.git"
  }

  expect_failures = [var.repository_url]
}
