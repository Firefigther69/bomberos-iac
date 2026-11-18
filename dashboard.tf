############################################
# Dashboard operativo
# Organizado de arriba hacia abajo: estado general -> usuario -> host -> seguridad -> pipeline.
############################################
locals {
  iid            = aws_instance.app.id
  dashboard_name = "${local.name_prefix}-operaciones"

  security_metrics = [for k, v in local.security_metric_filters : [local.metrics_namespace_security, v.metric, { label = v.metric }]]

  # Índice sobre una tupla: permite elegir entre dos widgets de estructura distinta.
  pipeline_widget = [
    {
      type = "metric", x = 12, y = 18, width = 12, height = 6
      properties = {
        title  = "Pipeline CodeBuild"
        region = local.region
        stat   = "Sum"
        period = 3600
        view   = "bar"
        metrics = [
          ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", "${local.name_prefix}-validate", { label = "validate OK", color = "#2ca02c" }],
          ["AWS/CodeBuild", "FailedBuilds", "ProjectName", "${local.name_prefix}-validate", { label = "validate fallido", color = "#d13212" }],
          ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", "${local.name_prefix}-integration", { label = "integration OK", color = "#1f77b4" }],
          ["AWS/CodeBuild", "FailedBuilds", "ProjectName", "${local.name_prefix}-integration", { label = "integration fallido", color = "#ff7f0e" }],
        ]
      }
    },
    {
      type = "text", x = 12, y = 18, width = 12, height = 6
      properties = {
        markdown = "### Pipeline\nEn este ambiente (AWS Academy Learner Lab) CodeBuild está deshabilitado porque la cuenta no permite crear su rol de servicio. La validación se ejecuta en **GitHub Actions** y las pruebas de integración con `scripts/deploy.sh`."
      }
    },
  ][var.enable_codebuild ? 0 : 1]

  dashboard_widgets = [
    {
      type = "text", x = 0, y = 0, width = 24, height = 2
      properties = {
        markdown = "## ${local.name_prefix} · Sistema de Gestión Operativa 3ra Compañía\nInstancia `${local.iid}` · Región `${local.region}` · Alertas al tópico `${aws_sns_topic.alerts.name}` · [Logs Insights](https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:logs-insights)"
      }
    },
    {
      type = "alarm", x = 0, y = 2, width = 24, height = 4
      properties = {
        title = "Estado de alarmas"
        alarms = concat(
          [aws_cloudwatch_composite_alarm.service_degraded.arn],
          [
            aws_cloudwatch_metric_alarm.status_check_failed.arn,
            aws_cloudwatch_metric_alarm.nginx_down.arn,
            aws_cloudwatch_metric_alarm.http_5xx.arn,
            aws_cloudwatch_metric_alarm.latency_high.arn,
            aws_cloudwatch_metric_alarm.cpu_high.arn,
            aws_cloudwatch_metric_alarm.memory_high.arn,
            aws_cloudwatch_metric_alarm.disk_high.arn,
            aws_cloudwatch_metric_alarm.agent_heartbeat.arn,
          ],
          [for a in aws_cloudwatch_metric_alarm.security : a.arn],
        )
      }
    },
    {
      type = "metric", x = 0, y = 6, width = 8, height = 6
      properties = {
        title   = "Solicitudes HTTP por clase"
        region  = local.region
        stat    = "Sum"
        period  = 300
        view    = "timeSeries"
        stacked = true
        metrics = [
          [local.metrics_namespace_app, "HTTPRequests", { label = "Total" }],
          [local.metrics_namespace_app, "HTTP4xx", { label = "4xx", color = "#ff9900" }],
          [local.metrics_namespace_app, "HTTP5xx", { label = "5xx", color = "#d13212" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 6, width = 8, height = 6
      properties = {
        title  = "Tiempo de respuesta (s)"
        region = local.region
        period = 300
        view   = "timeSeries"
        metrics = [
          [local.metrics_namespace_app, "ResponseTime", { stat = "p50", label = "p50" }],
          [local.metrics_namespace_app, "ResponseTime", { stat = "p90", label = "p90" }],
          [local.metrics_namespace_app, "ResponseTime", { stat = "Maximum", label = "máximo" }],
        ]
        annotations = { horizontal = [{ label = "Umbral", value = var.latency_threshold_seconds }] }
      }
    },
    {
      type = "metric", x = 16, y = 6, width = 8, height = 6
      properties = {
        title  = "Procesos nginx y errores"
        region = local.region
        period = 60
        view   = "timeSeries"
        metrics = [
          [local.metrics_namespace_ec2, "procstat_lookup_pid_count", "InstanceId", local.iid, "exe", "nginx", "pid_finder", "native", { stat = "Minimum", label = "procesos nginx" }],
          [local.metrics_namespace_app, "NginxErrors", { stat = "Sum", label = "errores nginx", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 12, width = 6, height = 6
      properties = {
        title  = "CPU (%)"
        region = local.region
        period = 60
        view   = "timeSeries"
        yAxis  = { left = { min = 0, max = 100 } }
        metrics = [
          ["AWS/EC2", "CPUUtilization", "InstanceId", local.iid, { stat = "Average", label = "CPU" }],
          [local.metrics_namespace_ec2, "cpu_usage_iowait", "InstanceId", local.iid, "cpu", "cpu-total", { stat = "Average", label = "iowait" }],
        ]
        annotations = { horizontal = [{ label = "Umbral", value = var.cpu_alarm_threshold }] }
      }
    },
    {
      type = "metric", x = 6, y = 12, width = 6, height = 6
      properties = {
        title  = "Memoria y disco (%)"
        region = local.region
        period = 300
        view   = "timeSeries"
        yAxis  = { left = { min = 0, max = 100 } }
        metrics = [
          [local.metrics_namespace_ec2, "mem_used_percent", "InstanceId", local.iid, { stat = "Average", label = "memoria" }],
          [local.metrics_namespace_ec2, "disk_used_percent", "InstanceId", local.iid, "path", "/", "fstype", "xfs", { stat = "Maximum", label = "disco /" }],
          [local.metrics_namespace_ec2, "swap_used_percent", "InstanceId", local.iid, { stat = "Average", label = "swap" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 12, width = 6, height = 6
      properties = {
        title  = "Red (bytes por 5 min)"
        region = local.region
        period = 300
        stat   = "Sum"
        view   = "timeSeries"
        metrics = [
          ["AWS/EC2", "NetworkIn", "InstanceId", local.iid, { label = "entrada" }],
          ["AWS/EC2", "NetworkOut", "InstanceId", local.iid, { label = "salida" }],
        ]
      }
    },
    {
      type = "metric", x = 18, y = 12, width = 6, height = 6
      properties = {
        title  = "Estado de instancia y créditos CPU"
        region = local.region
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/EC2", "StatusCheckFailed", "InstanceId", local.iid, { stat = "Maximum", label = "status check fallido" }],
          ["AWS/EC2", "CPUCreditBalance", "InstanceId", local.iid, { stat = "Minimum", label = "créditos CPU", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 18, width = 12, height = 6
      properties = {
        title   = "Eventos de seguridad (CloudTrail)"
        region  = local.region
        stat    = "Sum"
        period  = 300
        view    = "bar"
        metrics = local.security_metrics
      }
    },
    local.pipeline_widget,
    {
      type = "log", x = 0, y = 24, width = 12, height = 6
      properties = {
        title  = "Últimos errores 5xx"
        region = local.region
        view   = "table"
        query  = "SOURCE '${aws_cloudwatch_log_group.app["nginx_access"].name}' | fields @timestamp, status, method, uri, request_time | filter status >= 500 | sort @timestamp desc | limit 20"
      }
    },
    {
      type = "log", x = 12, y = 24, width = 12, height = 6
      properties = {
        title  = "Accesos denegados (CloudTrail)"
        region = local.region
        view   = "table"
        query  = "SOURCE '${aws_cloudwatch_log_group.cloudtrail.name}' | fields @timestamp, eventName, errorCode, userIdentity.arn, sourceIPAddress | filter errorCode like /AccessDenied|UnauthorizedOperation/ | sort @timestamp desc | limit 20"
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
