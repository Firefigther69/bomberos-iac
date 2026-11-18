############################################
# AMI: Amazon Linux 2023 más reciente, resuelta desde el parámetro público de
# AWS. Evita fijar IDs de AMI por región y asegura parches de base al día.
############################################
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

############################################
# Servidor de aplicación
############################################
resource "aws_instance" "app" {
  #checkov:skip=CKV_AWS_88:Decisión de arquitectura (ADR-02): IP pública sin puertos administrativos, evita NAT/ALB por costo; SG solo permite 80 de entrada
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = local.ec2_instance_profile_name
  associate_public_ip_address = true
  monitoring                  = true # Métricas EC2 cada 1 minuto: detección más temprana.
  ebs_optimized               = true

  # Sin key_name: no existe llave SSH. El acceso administrativo es por Session Manager.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio (mitiga SSRF).
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
  }

  credit_specification {
    cpu_credits = "standard" # Evita cargos por créditos ilimitados.
  }

  user_data = templatefile("${path.module}/scripts/user_data.sh.tftpl", {
    region              = local.region
    ssm_prefix          = local.ssm_prefix
    cw_agent_param_name = aws_ssm_parameter.cw_agent_config.name
    app_index_b64       = filebase64("${path.module}/app/index.html")
    environment         = var.environment
  })
  user_data_replace_on_change = true

  tags = {
    Name   = "${local.name_prefix}-app"
    Role   = "web"
    Backup = "daily"
  }

  lifecycle {
    ignore_changes = [ami] # Las nuevas AMI se aplican con un reemplazo planificado, no en cada plan.
  }

  depends_on = [
    aws_cloudwatch_log_group.app,
    aws_ssm_parameter.app_secret,
    aws_iam_role_policy.ec2,
  ]
}
