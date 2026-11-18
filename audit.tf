############################################
# Auditoría y trazabilidad: AWS CloudTrail
#
# - Multi-región y eventos globales: ninguna acción de la cuenta queda fuera.
# - Validación de integridad (digest firmado): prueba que los registros no fueron alterados.
# - Cifrado con la CMK y copia en CloudWatch Logs para alarmas en minutos.
# - Eventos de datos sobre el bucket de artefactos: traza quién modifica lo
#   que produce el pipeline.
############################################
resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_252:SNS por cada entrega de archivo genera ruido; las alertas se emiten por filtros de métricas y EventBridge
  count = var.enable_cloudtrail ? 1 : 0

  name                          = local.trail_name
  s3_bucket_name                = module.trail_bucket.id
  kms_key_id                    = aws_kms_key.main.arn
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  cloud_watch_logs_group_arn = var.cloudtrail_to_cloudwatch ? "${aws_cloudwatch_log_group.cloudtrail.arn}:*" : null
  cloud_watch_logs_role_arn  = var.cloudtrail_to_cloudwatch ? local.cloudtrail_logs_role_arn : null

  advanced_event_selector {
    name = "Eventos de administracion (lectura y escritura)"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Eventos de datos de escritura sobre artefactos del pipeline"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["${module.artifacts_bucket.arn}/"]
    }

    field_selector {
      field  = "readOnly"
      equals = ["false"]
    }
  }

  depends_on = [
    module.trail_bucket,
    aws_iam_role_policy.cloudtrail_logs,
  ]
}

############################################
# Filtros de seguridad sobre CloudTrail (CIS AWS Foundations, sección de monitoreo)
############################################
locals {
  security_metric_filters = {
    unauthorized_api_calls = {
      metric      = "UnauthorizedAPICalls"
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      threshold   = 5
      description = "RS-07: 5 o más llamadas API denegadas en 5 minutos. Posible abuso de credenciales o permisos mal asignados."
    }
    console_login_without_mfa = {
      metric      = "ConsoleLoginWithoutMFA"
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
      threshold   = 1
      description = "RS-03: inicio de sesión en consola sin MFA."
    }
    console_login_failures = {
      metric      = "ConsoleLoginFailures"
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"
      threshold   = 3
      description = "RS-03: 3 o más fallos de autenticación en consola en 5 minutos. Posible fuerza bruta."
    }
    root_account_usage = {
      metric      = "RootAccountUsage"
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      threshold   = 1
      description = "RS-03: uso de la cuenta raíz. Debe ser excepcional y justificado."
    }
    iam_policy_changes = {
      metric      = "IAMPolicyChanges"
      pattern     = "{ ($.eventSource = \"iam.amazonaws.com\") && (($.eventName = \"DeleteGroupPolicy\") || ($.eventName = \"DeleteRolePolicy\") || ($.eventName = \"DeleteUserPolicy\") || ($.eventName = \"PutGroupPolicy\") || ($.eventName = \"PutRolePolicy\") || ($.eventName = \"PutUserPolicy\") || ($.eventName = \"CreatePolicy\") || ($.eventName = \"DeletePolicy\") || ($.eventName = \"CreatePolicyVersion\") || ($.eventName = \"DeletePolicyVersion\") || ($.eventName = \"AttachRolePolicy\") || ($.eventName = \"DetachRolePolicy\") || ($.eventName = \"AttachUserPolicy\") || ($.eventName = \"DetachUserPolicy\") || ($.eventName = \"AttachGroupPolicy\") || ($.eventName = \"DetachGroupPolicy\") || ($.eventName = \"CreateAccessKey\")) }"
      threshold   = 1
      description = "RS-01: cambio en políticas IAM o creación de llaves de acceso fuera del pipeline."
    }
    security_group_changes = {
      metric      = "SecurityGroupChanges"
      pattern     = "{ ($.eventName = \"AuthorizeSecurityGroupIngress\") || ($.eventName = \"AuthorizeSecurityGroupEgress\") || ($.eventName = \"RevokeSecurityGroupIngress\") || ($.eventName = \"RevokeSecurityGroupEgress\") || ($.eventName = \"CreateSecurityGroup\") || ($.eventName = \"DeleteSecurityGroup\") || ($.eventName = \"ModifySecurityGroupRules\") }"
      threshold   = 1
      description = "RS-04: cambio en grupos de seguridad. Puede abrir puertos no autorizados."
    }
    network_changes = {
      metric      = "NetworkConfigChanges"
      pattern     = "{ ($.eventName = \"CreateRoute\") || ($.eventName = \"DeleteRoute\") || ($.eventName = \"ReplaceRoute\") || ($.eventName = \"CreateNetworkAcl\") || ($.eventName = \"CreateNetworkAclEntry\") || ($.eventName = \"DeleteNetworkAcl\") || ($.eventName = \"DeleteNetworkAclEntry\") || ($.eventName = \"AttachInternetGateway\") || ($.eventName = \"DetachInternetGateway\") || ($.eventName = \"ModifyVpcAttribute\") }"
      threshold   = 1
      description = "RS-04: cambio en rutas, NACL o gateways de la VPC."
    }
    cloudtrail_changes = {
      metric      = "CloudTrailConfigChanges"
      pattern     = "{ ($.eventName = \"CreateTrail\") || ($.eventName = \"UpdateTrail\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"StartLogging\") || ($.eventName = \"StopLogging\") || ($.eventName = \"PutEventSelectors\") }"
      threshold   = 1
      description = "RS-06: cambio en la configuración de auditoría. Detener el trail elimina la trazabilidad."
    }
    kms_key_disable_or_delete = {
      metric      = "KMSKeyDisableOrDeletion"
      pattern     = "{ ($.eventSource = \"kms.amazonaws.com\") && (($.eventName = \"DisableKey\") || ($.eventName = \"ScheduleKeyDeletion\")) }"
      threshold   = 1
      description = "RS-05: deshabilitación o eliminación programada de una CMK. Dejaría datos cifrados inaccesibles."
    }
    s3_policy_changes = {
      metric      = "S3BucketPolicyChanges"
      pattern     = "{ ($.eventSource = \"s3.amazonaws.com\") && (($.eventName = \"PutBucketAcl\") || ($.eventName = \"PutBucketPolicy\") || ($.eventName = \"DeleteBucketPolicy\") || ($.eventName = \"PutBucketPublicAccessBlock\") || ($.eventName = \"DeleteBucketPublicAccessBlock\") || ($.eventName = \"PutBucketEncryption\") || ($.eventName = \"DeleteBucketEncryption\")) }"
      threshold   = 1
      description = "RS-05: cambio en políticas, acceso público o cifrado de buckets."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "security" {
  for_each = local.security_metric_filters

  name           = "${local.name_prefix}-sec-${each.key}"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric
    namespace     = local.metrics_namespace_security
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "security" {
  for_each = local.security_metric_filters

  alarm_name          = "${local.name_prefix}-sec-${replace(each.key, "_", "-")}"
  alarm_description   = each.value.description
  namespace           = local.metrics_namespace_security
  metric_name         = each.value.metric
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.security]
}

############################################
# Notificación en tiempo real (EventBridge)
# Complementa los filtros de métricas: llega en segundos y con el detalle del evento.
############################################
resource "aws_cloudwatch_event_rule" "critical_changes" {
  name        = "${local.name_prefix}-cambios-criticos"
  description = "Uso de cuenta raiz, detencion de CloudTrail o cambios en la CMK"

  event_pattern = jsonencode({
    "$or" = [
      {
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail        = { userIdentity = { type = ["Root"] } }
      },
      {
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail        = { eventName = ["StopLogging", "DeleteTrail", "UpdateTrail"] }
      },
      {
        source        = ["aws.kms"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail        = { eventName = ["DisableKey", "ScheduleKeyDeletion"] }
      },
    ]
  })
}

resource "aws_cloudwatch_event_target" "critical_changes_sns" {
  rule      = aws_cloudwatch_event_rule.critical_changes.name
  target_id = "sns-alertas"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      evento  = "$.detail.eventName"
      usuario = "$.detail.userIdentity.arn"
      ip      = "$.detail.sourceIPAddress"
      hora    = "$.time"
      region  = "$.region"
    }
    input_template = "\"[CRITICO] Evento <evento> ejecutado por <usuario> desde <ip> en <region> a las <hora>. Revisar CloudTrail.\""
  }
}

resource "aws_cloudwatch_event_rule" "codebuild_failures" {
  count = var.enable_codebuild ? 1 : 0

  name        = "${local.name_prefix}-pipeline-fallido"
  description = "Notifica ejecuciones fallidas de los proyectos CodeBuild del proyecto"

  event_pattern = jsonencode({
    source        = ["aws.codebuild"]
    "detail-type" = ["CodeBuild Build State Change"]
    detail = {
      "build-status" = ["FAILED", "FAULT", "TIMED_OUT"]
      "project-name" = [aws_codebuild_project.validate[0].name, aws_codebuild_project.integration[0].name]
    }
  })
}

resource "aws_cloudwatch_event_target" "codebuild_failures_sns" {
  count = var.enable_codebuild ? 1 : 0

  rule      = aws_cloudwatch_event_rule.codebuild_failures[0].name
  target_id = "sns-alertas"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      proyecto = "$.detail.project-name"
      estado   = "$.detail.build-status"
      build    = "$.detail.build-id"
    }
    input_template = "\"[PIPELINE] El proyecto <proyecto> terminó en estado <estado>. Build: <build>\""
  }
}
