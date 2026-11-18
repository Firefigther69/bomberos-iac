############################################
# Grupo de seguridad del servidor de aplicación
#
# - Sin puerto 22: la administración se realiza con SSM Session Manager,
#   que no requiere puertos de entrada ni llaves SSH y deja registro auditable.
# - Entrada: solo HTTP (80) desde los orígenes autorizados.
# - Salida: solo HTTPS (443), suficiente para repositorios dnf de Amazon
#   Linux, endpoints de SSM, CloudWatch y KMS. El DNS (VPC resolver) y NTP
#   (Amazon Time Sync, 169.254.169.123) no atraviesan el grupo de seguridad.
############################################
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Servidor web: HTTP de entrada desde origenes autorizados, HTTPS de salida"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  #checkov:skip=CKV_AWS_260:Aplicación web de uso público para voluntarios; origen parametrizado en allowed_http_cidrs
  # count (no for_each): permite que la política propia CKV2_BOMB_5 evalúe la regla.
  count = length(var.allowed_http_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTP aplicacion desde ${var.allowed_http_cidrs[count.index]}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.allowed_http_cidrs[count.index]

  tags = { Name = "${local.name_prefix}-in-http" }
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS saliente: actualizaciones, SSM, CloudWatch y KMS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.name_prefix}-out-https" }
}
