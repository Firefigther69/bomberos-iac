############################################
# Gestión de secretos
#
# - Ninguna credencial se escribe en el código ni en variables .tfvars.
# - La credencial de la aplicación se genera en el despliegue y se guarda como
#   SecureString cifrada con la CMK del proyecto.
# - La instancia la lee en el arranque mediante su rol IAM (sin llaves de acceso),
#   restringida al prefijo /bomberos-la3/<env>/ y a descifrado vía SSM.
# - El estado de Terraform contiene el valor generado: por eso el backend remoto
#   debe ser un bucket S3 cifrado, versionado y con bloqueo (ver backend.hcl.example).
############################################
resource "random_password" "app_secret" {
  length           = 32
  special          = true
  override_special = "!#%*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_ssm_parameter" "app_secret" {
  name        = "${local.ssm_prefix}/app/session-secret"
  description = "Secreto de firma de sesiones de la aplicacion web"
  type        = "SecureString"
  key_id      = aws_kms_key.main.arn
  value       = random_password.app_secret.result
  tier        = "Standard"

  tags = { DataClassification = "confidential" }
}

resource "aws_ssm_parameter" "app_config" {
  #checkov:skip=CKV2_AWS_34:Configuración no sensible; el secreto está en app_secret (SecureString + CMK)
  name        = "${local.ssm_prefix}/app/config"
  description = "Configuracion no sensible de la aplicacion"
  type        = "String"
  value = jsonencode({
    environment  = var.environment
    company      = "3ra Compania de Bomberos de Los Angeles"
    health_path  = "/health"
    log_level    = var.environment == "prod" ? "warn" : "info"
    metrics_ns   = local.metrics_namespace_ec2
    log_group_fx = local.log_groups.nginx_access
  })
}
