# Pruebas unitarias de seguridad (RS-*). Proveedor simulado: sin credenciales ni costo.

mock_provider "aws" {
  source = "./tests/mocks"
}

mock_provider "random" {}

variables {
  environment = "dev"
}

run "rs02_instancia_endurecida" {
  command = apply

  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required"
    error_message = "RS-02: la instancia debe exigir IMDSv2 (http_tokens = required)."
  }

  assert {
    condition     = aws_instance.app.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "RS-02: el hop limit de IMDS debe ser 1 para impedir acceso desde contenedores."
  }

  assert {
    condition     = aws_instance.app.root_block_device[0].encrypted == true
    error_message = "RS-05: el volumen raíz debe estar cifrado."
  }

  assert {
    condition     = aws_instance.app.root_block_device[0].kms_key_id == aws_kms_key.main.arn
    error_message = "RS-05: el volumen raíz debe cifrarse con la CMK del proyecto."
  }

  assert {
    condition     = aws_instance.app.key_name == null || aws_instance.app.key_name == ""
    error_message = "RS-04: la instancia no debe tener llave SSH asociada (acceso solo por Session Manager)."
  }
}

run "rs04_red_restringida" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.app_http : r.from_port == 80 && r.to_port == 80])
    error_message = "RS-04: el único puerto de entrada permitido es 80."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.app_http : !(r.from_port <= 22 && r.to_port >= 22)])
    error_message = "RS-04: ninguna regla de entrada puede exponer SSH (22)."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.app_https.from_port == 443 && aws_vpc_security_group_egress_rule.app_https.to_port == 443
    error_message = "RS-04: la salida debe limitarse a HTTPS (443)."
  }

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "RS-04: el grupo de seguridad por defecto de la VPC debe quedar sin reglas."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "RS-04: las subredes no deben asignar IP pública automáticamente."
  }
}

run "rs05_cifrado_y_buckets" {
  command = plan

  assert {
    condition     = aws_kms_key.main.enable_key_rotation == true
    error_message = "RS-05: la CMK debe tener rotación automática habilitada."
  }

  assert {
    condition = alltrue([
      module.trail_bucket.id != "",
      module.artifacts_bucket.id != "",
      module.access_logs_bucket.id != "",
    ])
    error_message = "RS-05: deben existir los tres buckets endurecidos."
  }

  assert {
    condition     = aws_sns_topic.alerts.kms_master_key_id == aws_kms_key.main.arn
    error_message = "RS-05: el tópico de alertas debe cifrarse con la CMK."
  }

  assert {
    condition     = aws_ssm_parameter.app_secret.type == "SecureString"
    error_message = "RS-06: el secreto de la aplicación debe almacenarse como SecureString."
  }
}

run "rs01_minimo_privilegio_cuenta_propia" {
  command = plan

  variables {
    use_lab_role = false
  }

  assert {
    condition     = length(aws_iam_role.ec2) == 1 && length(aws_iam_role.codebuild) == 1
    error_message = "RS-01: en cuenta propia deben crearse roles dedicados por función."
  }

  assert {
    condition     = aws_iam_role.ec2[0].max_session_duration <= 3600
    error_message = "RS-01: las sesiones del rol EC2 no deben superar 1 hora."
  }

  assert {
    condition     = aws_iam_account_password_policy.strict[0].minimum_password_length >= 14
    error_message = "RS-03: la política de contraseñas debe exigir al menos 14 caracteres."
  }
}

run "rnf07_modo_learner_lab" {
  command = plan

  variables {
    use_lab_role     = true
    enable_codebuild = false
  }

  assert {
    condition     = length(aws_iam_role.ec2) == 0 && length(aws_iam_role.codebuild) == 0
    error_message = "RNF-07: en Learner Lab no deben intentarse roles nuevos (la cuenta lo prohíbe)."
  }

  assert {
    condition     = aws_instance.app.iam_instance_profile == "LabInstanceProfile"
    error_message = "RNF-07: en Learner Lab la instancia debe usar LabInstanceProfile."
  }

  assert {
    condition     = aws_flow_log.vpc.log_destination_type == "s3" && aws_flow_log.vpc.iam_role_arn == null
    error_message = "RNF-07: en Learner Lab los Flow Logs deben entregarse a S3 (LabRole no admite vpc-flow-logs)."
  }

  assert {
    condition     = length(aws_codebuild_project.validate) == 0 && length(aws_cloudwatch_metric_alarm.codebuild_failed) == 0
    error_message = "RNF-07: con enable_codebuild = false no deben crearse proyectos ni alarmas de CodeBuild."
  }
}
