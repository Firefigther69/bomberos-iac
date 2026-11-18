############################################
# Logging centralizado
#
# Todos los registros convergen en CloudWatch Logs, cifrados con la CMK y con
# retención definida. Cada grupo responde a un requerimiento (ver
# docs/01-requerimientos.md y docs/03-matriz-trazabilidad.md).
############################################
resource "aws_cloudwatch_log_group" "app" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = { LogSource = each.key }
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/${var.project_name}/${var.environment}/audit/cloudtrail"
  retention_in_days = max(var.log_retention_days, 365) # Auditoría: mínimo 1 año aunque se reduzca el resto.
  kms_key_id        = aws_kms_key.main.arn

  tags = { LogSource = "cloudtrail" }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/${var.project_name}/${var.environment}/cicd/codebuild"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = { LogSource = "codebuild" }
}

############################################
# Configuración del agente CloudWatch (versionada en Parameter Store)
############################################
resource "aws_ssm_parameter" "cw_agent_config" {
  #checkov:skip=CKV2_AWS_34:Configuración no sensible del agente; los secretos usan SecureString con CMK
  name        = "${local.ssm_prefix}/cloudwatch-agent/config"
  description = "Configuracion del agente CloudWatch: metricas del SO y envio de logs"
  type        = "String"
  tier        = "Standard"

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      logfile                     = "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
    }
    metrics = {
      namespace         = local.metrics_namespace_ec2
      append_dimensions = { InstanceId = "$${aws:InstanceId}" }
      metrics_collected = {
        cpu = {
          measurement = ["cpu_usage_iowait", "cpu_usage_steal", "cpu_usage_user", "cpu_usage_system"]
          totalcpu    = true
        }
        mem = {
          measurement = ["mem_used_percent", "mem_available_percent"]
        }
        swap = {
          measurement = ["swap_used_percent"]
        }
        disk = {
          measurement              = ["used_percent", "inodes_free"]
          resources                = ["/"]
          drop_device              = true
          ignore_file_system_types = ["sysfs", "tmpfs", "devtmpfs", "overlay"]
        }
        diskio = {
          measurement = ["io_time", "read_bytes", "write_bytes"]
          resources   = ["*"]
        }
        netstat = {
          measurement = ["tcp_established", "tcp_time_wait"]
        }
        procstat = [{
          exe         = "nginx"
          measurement = ["pid_count", "cpu_usage", "memory_rss"]
        }]
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/nginx/access.json"
              log_group_name  = local.log_groups.nginx_access
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/nginx/error.log"
              log_group_name  = local.log_groups.nginx_error
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/messages"
              log_group_name  = local.log_groups.system
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/secure"
              log_group_name  = local.log_groups.secure
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
              log_group_name  = local.log_groups.cw_agent
              log_stream_name = "{instance_id}"
            },
          ]
        }
      }
    }
  })
}

############################################
# Métricas derivadas de logs de la aplicación
############################################
locals {
  app_metric_filters = {
    http_requests = {
      log_group = "nginx_access"
      pattern   = "{ $.status > 0 }"
      metric    = "HTTPRequests"
      value     = "1"
      unit      = "Count"
    }
    http_4xx = {
      log_group = "nginx_access"
      pattern   = "{ $.status >= 400 && $.status < 500 }"
      metric    = "HTTP4xx"
      value     = "1"
      unit      = "Count"
    }
    http_5xx = {
      log_group = "nginx_access"
      pattern   = "{ $.status >= 500 }"
      metric    = "HTTP5xx"
      value     = "1"
      unit      = "Count"
    }
    response_time = {
      log_group = "nginx_access"
      pattern   = "{ $.request_time >= 0 }"
      metric    = "ResponseTime"
      value     = "$.request_time"
      unit      = "Seconds"
    }
    nginx_errors = {
      log_group = "nginx_error"
      pattern   = "?\"[error]\" ?\"[crit]\" ?\"[alert]\" ?\"[emerg]\""
      metric    = "NginxErrors"
      value     = "1"
      unit      = "Count"
    }
    sudo_commands = {
      log_group = "secure"
      pattern   = "\"COMMAND=\""
      metric    = "HostSudoCommands"
      value     = "1"
      unit      = "Count"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "app" {
  for_each = local.app_metric_filters

  name           = "${local.name_prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.app[each.value.log_group].name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric
    namespace     = local.metrics_namespace_app
    value         = each.value.value
    unit          = each.value.unit
    default_value = each.value.value == "1" ? 0 : null
  }
}

############################################
# Consultas guardadas de Logs Insights (investigación de incidentes)
############################################
resource "aws_cloudwatch_query_definition" "http_errors" {
  name            = "${local.name_prefix}/app/errores-http-5xx"
  log_group_names = [aws_cloudwatch_log_group.app["nginx_access"].name]
  query_string    = <<-EOT
    fields @timestamp, status, method, uri, request_time, remote_addr, request_id
    | filter status >= 500
    | sort @timestamp desc
    | limit 100
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_requests" {
  name            = "${local.name_prefix}/app/solicitudes-lentas"
  log_group_names = [aws_cloudwatch_log_group.app["nginx_access"].name]
  query_string    = <<-EOT
    fields @timestamp, uri, request_time, status
    | filter request_time > ${var.latency_threshold_seconds}
    | stats count(*) as solicitudes, avg(request_time) as promedio, max(request_time) as maximo by uri
    | sort maximo desc
  EOT
}

resource "aws_cloudwatch_query_definition" "access_denied" {
  name            = "${local.name_prefix}/audit/accesos-denegados"
  log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
  query_string    = <<-EOT
    fields @timestamp, eventSource, eventName, errorCode, userIdentity.arn, sourceIPAddress
    | filter errorCode like /AccessDenied|UnauthorizedOperation/
    | sort @timestamp desc
    | limit 100
  EOT
}

resource "aws_cloudwatch_query_definition" "iam_activity" {
  name            = "${local.name_prefix}/audit/cambios-iam-y-red"
  log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
  query_string    = <<-EOT
    fields @timestamp, eventName, userIdentity.arn, sourceIPAddress, requestParameters.groupId, requestParameters.roleName
    | filter eventSource in ["iam.amazonaws.com", "ec2.amazonaws.com"]
      and eventName like /Put|Attach|Detach|Create|Delete|Authorize|Revoke/
    | sort @timestamp desc
    | limit 100
  EOT
}

resource "aws_cloudwatch_query_definition" "session_manager" {
  name            = "${local.name_prefix}/audit/sesiones-ssm"
  log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
  query_string    = <<-EOT
    fields @timestamp, eventName, userIdentity.arn, requestParameters.target, sourceIPAddress
    | filter eventSource = "ssm.amazonaws.com" and eventName in ["StartSession", "TerminateSession", "SendCommand"]
    | sort @timestamp desc
  EOT
}
