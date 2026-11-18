# Este archivo documenta el modo de ejecución: todos los archivos *.tftest.hcl
# usan proveedores simulados (mock_provider), por lo que `terraform test` corre
# sin credenciales ni costo, en local, en GitHub Actions y en CodeBuild.
#
# Cada `run` referencia el requerimiento que valida (ver docs/03-matriz-trazabilidad.md).

mock_provider "aws" {
  source = "./tests/mocks"
}

mock_provider "random" {}

variables {
  project_name = "bomberos-la3"
  environment  = "dev"
  alarm_email  = "alertas@example.com"
}

run "rf02_rt01_plan_base_sin_errores" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "RT-01: deben crearse dos subredes públicas en zonas distintas."
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.20.0.0/16" && aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "RF-02/RT-01: la red completa (VPC, rutas) debe declararse en código."
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone != aws_subnet.public[1].availability_zone
    error_message = "RT-01: las subredes deben quedar en zonas de disponibilidad diferentes."
  }
}
