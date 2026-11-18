############################################
# Pipeline DevOps en AWS CodeBuild
#
# validate     -> en cada cambio: formato, sintaxis, lint, políticas de seguridad
#                 (Checkov), búsqueda de secretos (gitleaks) y pruebas unitarias
#                 de Terraform con proveedor simulado. No requiere permisos sobre
#                 la infraestructura.
# integration  -> después del despliegue y de forma programada: verifica en la
#                 cuenta real que monitoreo, auditoría y seguridad estén activos.
#                 Solo lectura.
############################################
locals {
  codebuild_image = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"

  codebuild_common_env = {
    TF_VERSION       = var.terraform_version
    TF_IN_AUTOMATION = "true"
    PROJECT          = var.project_name
    ENVIRONMENT      = var.environment
  }

  # Solo identificadores no sensibles: las pruebas de integración consultan el estado real vía API.
  integration_env = {
    APP_URL            = "http://${aws_instance.app.public_ip}"
    INSTANCE_ID        = aws_instance.app.id
    SECURITY_GROUP_ID  = aws_security_group.app.id
    TRAIL_NAME         = local.trail_name
    SNS_TOPIC_ARN      = aws_sns_topic.alerts.arn
    DASHBOARD_NAME     = local.dashboard_name
    ALARM_PREFIX       = local.name_prefix
    KMS_KEY_ARN        = aws_kms_key.main.arn
    TRAIL_BUCKET       = module.trail_bucket.id
    ARTIFACTS_BUCKET   = module.artifacts_bucket.id
    ACCESS_LOGS_BUCKET = module.access_logs_bucket.id
    LOG_GROUP_PREFIX   = "/${var.project_name}/${var.environment}"
    VPC_ID             = aws_vpc.main.id
    METRICS_NAMESPACE  = local.metrics_namespace_ec2
  }
}

resource "aws_codebuild_project" "validate" {
  count = var.enable_codebuild ? 1 : 0

  name           = "${local.name_prefix}-validate"
  description    = "CI: fmt, validate, tflint, checkov, gitleaks y terraform test"
  service_role   = local.codebuild_role_arn
  encryption_key = aws_kms_key.main.arn
  build_timeout  = 20
  queued_timeout = 60

  source {
    type                = "GITHUB"
    location            = var.repository_url
    git_clone_depth     = 0 # Historial completo: gitleaks revisa todos los commits.
    buildspec           = "buildspec/validate.yml"
    report_build_status = false
  }

  source_version = var.repository_branch

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    dynamic "environment_variable" {
      for_each = local.codebuild_common_env
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  artifacts {
    type                = "S3"
    location            = module.artifacts_bucket.id
    path                = "validate"
    namespace_type      = "BUILD_ID"
    packaging           = "ZIP"
    encryption_disabled = false
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "validate"
    }
  }
}

resource "aws_codebuild_project" "integration" {
  count = var.enable_codebuild ? 1 : 0

  name           = "${local.name_prefix}-integration"
  description    = "CT: pruebas de integracion de solo lectura contra la infraestructura desplegada"
  service_role   = local.codebuild_role_arn
  encryption_key = aws_kms_key.main.arn
  build_timeout  = 15
  queued_timeout = 60

  source {
    type            = "GITHUB"
    location        = var.repository_url
    git_clone_depth = 1
    buildspec       = "buildspec/integration.yml"
  }

  source_version = var.repository_branch

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    dynamic "environment_variable" {
      for_each = merge(local.codebuild_common_env, local.integration_env)
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "integration"
    }
  }
}

############################################
# Verificación continua: pruebas de integración programadas
# Detecta deriva de configuración (alguien desactiva el trail, abre un puerto, etc.)
############################################
resource "aws_cloudwatch_event_rule" "integration_schedule" {
  count = var.enable_codebuild && var.integration_test_schedule != "" ? 1 : 0

  name                = "${local.name_prefix}-pruebas-integracion-programadas"
  description         = "Ejecuta diariamente las pruebas de integracion para detectar deriva"
  schedule_expression = var.integration_test_schedule
}

resource "aws_cloudwatch_event_target" "integration_schedule" {
  count = var.enable_codebuild && var.integration_test_schedule != "" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.integration_schedule[0].name
  target_id = "codebuild-integration"
  arn       = aws_codebuild_project.integration[0].arn
  role_arn  = local.events_role_arn
}

############################################
# Disparo automático en cada push / pull request (opcional)
############################################
resource "aws_codebuild_webhook" "validate" {
  count = var.enable_codebuild && var.enable_github_webhook ? 1 : 0

  project_name = aws_codebuild_project.validate[0].name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH,PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED,PULL_REQUEST_REOPENED"
    }
  }
}
