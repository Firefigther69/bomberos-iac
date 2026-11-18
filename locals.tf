data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Se toman solo las N primeras AZ disponibles mediante slice(); nuevas AZ no alteran las subredes existentes
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  partition   = data.aws_partition.current.partition

  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  # Ruta jerárquica de Parameter Store: permite acotar permisos IAM por prefijo.
  ssm_prefix = "/${var.project_name}/${var.environment}"

  # Espacios de nombres de métricas propias.
  metrics_namespace_ec2      = "BomberosLA3/EC2"
  metrics_namespace_app      = "BomberosLA3/App"
  metrics_namespace_security = "BomberosLA3/Security"

  log_groups = {
    nginx_access = "/${var.project_name}/${var.environment}/app/nginx-access"
    nginx_error  = "/${var.project_name}/${var.environment}/app/nginx-error"
    system       = "/${var.project_name}/${var.environment}/system/messages"
    secure       = "/${var.project_name}/${var.environment}/system/secure"
    cw_agent     = "/${var.project_name}/${var.environment}/system/cloudwatch-agent"
  }

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
    CostCenter  = "3ra-compania-bomberos-los-angeles"
    Repository  = var.repository_url
  }
}
