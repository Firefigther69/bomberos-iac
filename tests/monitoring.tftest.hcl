# Pruebas unitarias de monitoreo, logging y auditoría (RF-03, RF-04, RF-05, RNF-*).

mock_provider "aws" {
  source = "./tests/mocks"
}

mock_provider "random" {}

variables {
  environment        = "dev"
  alarm_email        = "alertas@example.com"
  log_retention_days = 365
}

run "rf04_logs_centralizados_y_cifrados" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_log_group.app) == 5
    error_message = "RF-04: deben existir los 5 grupos de logs del host (nginx access/error, messages, secure, agente)."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.app : lg.retention_in_days == 365])
    error_message = "RNF-05: todos los grupos de logs deben tener retención definida."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.app : lg.kms_key_id == aws_kms_key.main.arn])
    error_message = "RS-05: todos los grupos de logs deben cifrarse con la CMK."
  }

  assert {
    condition     = aws_cloudwatch_log_group.cloudtrail.retention_in_days >= 365
    error_message = "RF-05: los logs de auditoría deben retenerse al menos 1 año."
  }

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL"
    error_message = "RF-04: los VPC Flow Logs deben registrar tráfico aceptado y rechazado."
  }
}

run "rf03_metricas_del_sistema_operativo" {
  command = plan

  assert {
    condition = alltrue([
      for m in ["mem", "disk", "swap", "netstat", "procstat", "cpu"] :
      contains(keys(jsondecode(aws_ssm_parameter.cw_agent_config.value).metrics.metrics_collected), m)
    ])
    error_message = "RF-03: el agente debe recolectar CPU, memoria, disco, swap, red (netstat) y procesos."
  }

  assert {
    condition     = jsondecode(aws_ssm_parameter.cw_agent_config.value).metrics.namespace == "BomberosLA3/EC2"
    error_message = "RF-03: las métricas del agente deben publicarse en el namespace del proyecto."
  }

  assert {
    condition     = length(jsondecode(aws_ssm_parameter.cw_agent_config.value).logs.logs_collected.files.collect_list) == 5
    error_message = "RF-04: el agente debe enviar los 5 archivos de log definidos."
  }

  assert {
    condition     = aws_instance.app.monitoring == true
    error_message = "RNF-02: la instancia debe tener monitoreo detallado (1 minuto)."
  }
}

run "rf03_alarmas_de_deteccion_temprana" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high.threshold == var.cpu_alarm_threshold
    error_message = "RNF-02: la alarma de CPU debe usar el umbral parametrizado."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.memory_high.metric_name == "mem_used_percent"
    error_message = "RNF-02: debe existir alarma de memoria basada en el agente."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_high.dimensions["path"] == "/"
    error_message = "RNF-02: la alarma de disco debe vigilar el sistema de archivos raíz."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.agent_heartbeat.treat_missing_data == "breaching"
    error_message = "RF-04: la pérdida de telemetría del agente debe tratarse como incidente."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.nginx_down.treat_missing_data == "breaching"
    error_message = "RF-01: la ausencia del proceso nginx debe tratarse como incidente."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.network_anomaly) == 2
    error_message = "RNF-02: deben existir alarmas de anomalía para tráfico de entrada y salida."
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.system_check_failed.alarm_actions, "arn:aws:automate:us-east-1:ec2:recover")
    error_message = "RNF-01: la falla de sistema debe disparar la recuperación automática."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.app) == 6
    error_message = "RF-03: deben existir los 6 filtros de métricas de aplicación."
  }
}

run "rf05_alarmas_notifican_por_sns" {
  command = apply

  assert {
    condition = alltrue(concat(
      [for a in aws_cloudwatch_metric_alarm.security : contains(a.alarm_actions, aws_sns_topic.alerts.arn)],
      [contains(aws_cloudwatch_metric_alarm.cpu_high.alarm_actions, aws_sns_topic.alerts.arn)],
      [contains(aws_cloudwatch_metric_alarm.http_5xx.alarm_actions, aws_sns_topic.alerts.arn)],
    ))
    error_message = "RF-05: todas las alarmas deben notificar al tópico SNS de alertas."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "RF-05: con alarm_email definido debe crearse la suscripción de correo."
  }
}

run "rf05_auditoria_cloudtrail" {
  command = plan

  assert {
    condition     = aws_cloudtrail.main[0].is_multi_region_trail == true
    error_message = "RF-05: el trail debe ser multi-región."
  }

  assert {
    condition     = aws_cloudtrail.main[0].enable_log_file_validation == true
    error_message = "RF-05: el trail debe validar la integridad de los archivos de log."
  }

  assert {
    condition     = aws_cloudtrail.main[0].include_global_service_events == true
    error_message = "RF-05: el trail debe incluir eventos de servicios globales (IAM, STS)."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.security) >= 10
    error_message = "RS-07: deben existir al menos 10 alarmas de seguridad sobre CloudTrail."
  }
}

run "rf06_rs09_pipeline_registrado_y_cifrado" {
  command = apply

  assert {
    condition     = aws_codebuild_project.validate[0].encryption_key == aws_kms_key.main.arn
    error_message = "RS-09: los artefactos de CodeBuild deben cifrarse con la CMK."
  }

  assert {
    condition     = aws_codebuild_project.validate[0].environment[0].privileged_mode == false
    error_message = "RS-09: CodeBuild no debe ejecutarse en modo privilegiado."
  }

  assert {
    condition     = aws_codebuild_project.integration[0].source[0].buildspec == "buildspec/integration.yml"
    error_message = "RF-06: el proyecto de integración debe usar su buildspec dedicado."
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.integration_schedule) == 1
    error_message = "RF-06: las pruebas de integración deben programarse para detectar deriva."
  }
}
