############################################
# Alarmas de detección temprana
#
# Criterios de diseño:
# - Umbrales parametrizados (variables.tf) para ajustarlos sin tocar código.
# - Evaluación "M de N" para evitar falsos positivos por picos aislados.
# - treat_missing_data explícito: cuando la ausencia de datos ES el incidente
#   (agente o nginx caídos) se trata como "breaching".
# - Todas notifican al tópico SNS cifrado, también al volver a OK.
############################################
locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  instance_dims = { InstanceId = aws_instance.app.id }
  recover_arn   = "arn:${local.partition}:automate:${local.region}:ec2:recover"
}

############################################
# Infraestructura (EC2 nativo)
############################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-ec2-cpu-alta"
  alarm_description   = "RNF-02: CPU sobre ${var.cpu_alarm_threshold}% en 2 de 3 periodos de 5 min. Posible saturación o proceso descontrolado."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = local.instance_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "cpu_credits_low" {
  alarm_name          = "${local.name_prefix}-ec2-creditos-cpu-bajos"
  alarm_description   = "RNF-02: saldo de créditos de CPU (instancia burstable) bajo 20. Anticipa degradación por throttling."
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  dimensions          = local.instance_dims
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 20
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "${local.name_prefix}-ec2-status-check"
  alarm_description   = "RNF-01: falla de verificación de estado de instancia o sistema."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = local.instance_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "system_check_failed" {
  alarm_name          = "${local.name_prefix}-ec2-system-check-recuperacion"
  alarm_description   = "RNF-01: falla del hardware subyacente. Ejecuta recuperación automática de la instancia."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = local.instance_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
  alarm_actions       = var.enable_auto_recovery ? concat(local.alarm_actions, [local.recover_arn]) : local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "network_anomaly" {
  for_each = toset(["NetworkIn", "NetworkOut"])

  alarm_name          = "${local.name_prefix}-ec2-${lower(each.key)}-anomalia"
  alarm_description   = "RNF-02/RS-08: ${each.key} fuera de la banda esperada (detección de anomalías, 3 desviaciones). Puede indicar abuso, exfiltración o caída de tráfico."
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold_metric_id = "banda"
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      namespace   = "AWS/EC2"
      metric_name = each.key
      dimensions  = local.instance_dims
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "banda"
    expression  = "ANOMALY_DETECTION_BAND(m1, 3)"
    label       = "${each.key} esperado"
    return_data = true
  }
}

############################################
# Sistema operativo (agente CloudWatch)
############################################
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${local.name_prefix}-so-memoria-alta"
  alarm_description   = "RNF-02: memoria usada sobre ${var.memory_alarm_threshold}%. EC2 no expone esta métrica sin el agente."
  namespace           = local.metrics_namespace_ec2
  metric_name         = "mem_used_percent"
  dimensions          = local.instance_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_alarm_threshold
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name        = "${local.name_prefix}-so-disco-alto"
  alarm_description = "RNF-02: disco raíz sobre ${var.disk_alarm_threshold}%. Un disco lleno detiene nginx y la escritura de logs."
  namespace         = local.metrics_namespace_ec2
  metric_name       = "disk_used_percent"
  dimensions = {
    InstanceId = aws_instance.app.id
    path       = "/"
    fstype     = "xfs"
  }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.disk_alarm_threshold
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "agent_heartbeat" {
  alarm_name          = "${local.name_prefix}-so-agente-sin-datos"
  alarm_description   = "RF-04: el agente CloudWatch dejó de reportar. Sin él se pierde visibilidad de memoria, disco y logs."
  namespace           = local.metrics_namespace_ec2
  metric_name         = "mem_used_percent"
  dimensions          = local.instance_dims
  statistic           = "SampleCount"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "nginx_down" {
  alarm_name        = "${local.name_prefix}-app-nginx-detenido"
  alarm_description = "RF-01: no hay procesos nginx en ejecución. El servicio web está caído aunque la instancia siga activa."
  namespace         = local.metrics_namespace_ec2
  metric_name       = "procstat_lookup_pid_count"
  dimensions = {
    InstanceId = aws_instance.app.id
    exe        = "nginx"
    pid_finder = "native"
  }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

############################################
# Aplicación (métricas derivadas de logs)
############################################
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${local.name_prefix}-app-errores-5xx"
  alarm_description   = "RF-01: ${var.http_5xx_threshold} o más respuestas 5xx en 5 minutos. Error del servidor visible para los voluntarios."
  namespace           = local.metrics_namespace_app
  metric_name         = "HTTP5xx"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.http_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.app]
}

resource "aws_cloudwatch_metric_alarm" "latency_high" {
  alarm_name          = "${local.name_prefix}-app-latencia-alta"
  alarm_description   = "RNF-03: percentil 90 del tiempo de respuesta sobre ${var.latency_threshold_seconds}s en 2 de 3 periodos."
  namespace           = local.metrics_namespace_app
  metric_name         = "ResponseTime"
  extended_statistic  = "p90"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_threshold_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.app]
}

resource "aws_cloudwatch_metric_alarm" "nginx_errors" {
  alarm_name          = "${local.name_prefix}-app-errores-nginx"
  alarm_description   = "RF-04: más de 10 entradas error/crit/alert/emerg en el log de nginx en 5 minutos."
  namespace           = local.metrics_namespace_app
  metric_name         = "NginxErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.app]
}

############################################
# Pipeline
############################################
resource "aws_cloudwatch_metric_alarm" "codebuild_failed" {
  for_each = var.enable_codebuild ? {
    validate    = aws_codebuild_project.validate[0].name
    integration = aws_codebuild_project.integration[0].name
  } : {}

  alarm_name          = "${local.name_prefix}-cicd-${each.key}-fallido"
  alarm_description   = "RF-06: la ejecución ${each.key} del pipeline falló. Indica configuración no conforme o deriva de la infraestructura."
  namespace           = "AWS/CodeBuild"
  metric_name         = "FailedBuilds"
  dimensions          = { ProjectName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

############################################
# Alarma compuesta: estado de servicio
# Resume en una señal única si los voluntarios pueden usar el sistema.
############################################
resource "aws_cloudwatch_composite_alarm" "service_degraded" {
  alarm_name        = "${local.name_prefix}-servicio-degradado"
  alarm_description = "RF-01: el servicio web no está disponible o responde con errores (estado de instancia, nginx, 5xx o pérdida de telemetría)."
  alarm_actions     = local.alarm_actions
  ok_actions        = local.alarm_actions

  alarm_rule = join(" OR ", [
    "ALARM(\"${aws_cloudwatch_metric_alarm.status_check_failed.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.nginx_down.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.http_5xx.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.agent_heartbeat.alarm_name}\")",
  ])
}
