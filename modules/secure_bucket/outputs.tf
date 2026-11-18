output "id" {
  description = "Nombre (ID) del bucket."
  value       = local.bucket_id
}

output "arn" {
  description = "ARN del bucket."
  value       = local.bucket_arn
}

output "policy_dependency" {
  description = "ID de la política aplicada; permite a otros recursos esperar a que exista."
  value       = aws_s3_bucket_policy.this.id
}
