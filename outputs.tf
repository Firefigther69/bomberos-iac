output "app_url" {
  description = "URL pública de la aplicación."
  value       = "http://${aws_instance.app.public_ip}"
}

output "health_check_url" {
  description = "Endpoint de salud usado por las pruebas de humo."
  value       = "http://${aws_instance.app.public_ip}/health"
}

output "instance_id" {
  description = "ID de la instancia EC2 (acceso administrativo: aws ssm start-session --target <id>)."
  value       = aws_instance.app.id
}

output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.main.id
}

output "security_group_id" {
  description = "ID del grupo de seguridad de la aplicación."
  value       = aws_security_group.app.id
}

output "dashboard_url" {
  description = "Dashboard operativo de CloudWatch."
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "dashboard_name" {
  description = "Nombre del dashboard."
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "sns_topic_arn" {
  description = "Tópico SNS de alertas."
  value       = aws_sns_topic.alerts.arn
}

output "cloudtrail_name" {
  description = "Nombre del trail de auditoría."
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
}

output "log_groups" {
  description = "Grupos de logs creados por el proyecto."
  value = merge(
    { for k, lg in aws_cloudwatch_log_group.app : k => lg.name },
    {
      cloudtrail = aws_cloudwatch_log_group.cloudtrail.name
      codebuild  = aws_cloudwatch_log_group.codebuild.name
      vpc_flow   = aws_cloudwatch_log_group.vpc_flow_logs.name
    },
  )
}

output "buckets" {
  description = "Buckets S3 del proyecto."
  value = {
    cloudtrail  = module.trail_bucket.id
    artifacts   = module.artifacts_bucket.id
    access_logs = module.access_logs_bucket.id
  }
}

output "kms_key_arn" {
  description = "ARN de la CMK del proyecto."
  value       = aws_kms_key.main.arn
}

output "codebuild_projects" {
  description = "Proyectos CodeBuild del pipeline."
  value = var.enable_codebuild ? {
    validate    = aws_codebuild_project.validate[0].name
    integration = aws_codebuild_project.integration[0].name
  } : {}
}

output "alarm_prefix" {
  description = "Prefijo común de todas las alarmas."
  value       = local.name_prefix
}

output "metrics_namespace" {
  description = "Namespace de métricas del agente CloudWatch."
  value       = local.metrics_namespace_ec2
}

output "app_secret_parameter" {
  description = "Nombre del parámetro SecureString (el valor nunca se expone como output)."
  value       = aws_ssm_parameter.app_secret.name
}
