# Pruebas unitarias de requerimientos operativos, de rendimiento, costo y acceso
# (RF-07, RNF-03, RNF-04, RT-04, RT-06). Proveedor simulado: sin credenciales ni costo.

mock_provider "aws" {
  source = "./tests/mocks"
}

mock_provider "random" {}

run "rf07_administracion_sin_ssh" {
  command = apply

  assert {
    condition     = aws_instance.app.key_name == null || aws_instance.app.key_name == ""
    error_message = "RF-07: la instancia no debe tener llave SSH; la administración es por Session Manager."
  }

  assert {
    condition     = aws_instance.app.iam_instance_profile == aws_iam_instance_profile.ec2[0].name
    error_message = "RF-07: la instancia debe tener el perfil que habilita el agente SSM."
  }

  assert {
    condition     = length(aws_cloudwatch_query_definition.session_manager.query_string) > 0
    error_message = "RF-07: debe existir la consulta de auditoría de sesiones SSM."
  }
}

run "rnf03_alarma_de_latencia_p90" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.latency_high.extended_statistic == "p90"
    error_message = "RNF-03: la latencia debe evaluarse con el percentil 90."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.latency_high.threshold == 2
    error_message = "RNF-03: el umbral de latencia por defecto debe ser 2 segundos."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.app["response_time"].metric_transformation[0].value == "$.request_time"
    error_message = "RNF-03: la métrica ResponseTime debe tomarse del campo request_time del log JSON."
  }
}

run "rnf04_control_de_costos" {
  command = plan

  assert {
    condition     = aws_instance.app.credit_specification[0].cpu_credits == "standard"
    error_message = "RNF-04: la instancia burstable no debe usar créditos ilimitados (cargos variables)."
  }

  assert {
    condition     = aws_instance.app.instance_type == "t3.micro"
    error_message = "RNF-04: el tipo de instancia por defecto debe ser t3.micro."
  }

  assert {
    condition     = aws_instance.app.root_block_device[0].volume_type == "gp3"
    error_message = "RNF-04: el volumen raíz debe ser gp3 (menor costo por GiB que gp2)."
  }
}

run "rt04_servidor_al2023_con_agentes" {
  command = plan

  assert {
    condition     = data.aws_ssm_parameter.al2023_ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "RT-04: la AMI debe resolverse desde el parámetro público de Amazon Linux 2023."
  }

  assert {
    condition     = aws_ssm_parameter.cw_agent_config.name == "/bomberos-la3/dev/cloudwatch-agent/config"
    error_message = "RT-04: la configuración del agente CloudWatch debe publicarse en Parameter Store."
  }
}

run "rt06_region_por_defecto" {
  command = plan

  assert {
    condition     = var.aws_region == "us-east-1"
    error_message = "RT-06: la región por defecto debe ser us-east-1 (compatible con Learner Lab)."
  }
}

run "rf06_webhook_ejecuta_validate_en_cada_cambio" {
  command = plan

  variables {
    enable_github_webhook = true
  }

  assert {
    condition     = length(aws_codebuild_webhook.validate) == 1
    error_message = "RF-06: con enable_github_webhook = true cada push o PR debe disparar CodeBuild validate."
  }

  assert {
    condition     = anytrue(flatten([for g in aws_codebuild_webhook.validate[0].filter_group : [for f in g.filter : strcontains(f.pattern, "PULL_REQUEST_CREATED")]]))
    error_message = "RF-06: el webhook debe incluir los pull requests."
  }
}
