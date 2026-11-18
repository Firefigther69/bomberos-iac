provider "aws" {
  region = var.aws_region

  # Etiquetado obligatorio y homogéneo en todos los recursos: permite trazar
  # costos, propiedad y ambiente desde Cost Explorer y Resource Groups.
  default_tags {
    tags = local.common_tags
  }
}
