variable "bucket_name" {
  description = "Nombre global del bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "El nombre del bucket no cumple las reglas de nomenclatura de S3."
  }
}

variable "purpose" {
  description = "Propósito del bucket (se registra como etiqueta)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN de la CMK para SSE-KMS. null usa SSE-S3 (requerido por destinos de registro de acceso del servidor)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Permite eliminar el bucket aunque contenga objetos."
  type        = bool
  default     = false
}

variable "enable_access_logging" {
  description = "Habilita el registro de accesos del servidor. Se declara aparte del bucket destino para que count sea conocido en el plan."
  type        = bool
  default     = false
}

variable "access_log_bucket_id" {
  description = "Bucket destino del registro de accesos del servidor (requerido si enable_access_logging = true)."
  type        = string
  default     = null
}

variable "additional_policy_json" {
  description = "Política adicional que se fusiona con los controles base del bucket."
  type        = string
  default     = null
}

variable "transition_to_ia_days" {
  description = "Días antes de mover objetos a STANDARD_IA."
  type        = number
  default     = 30
}

variable "expiration_days" {
  description = "Días antes de expirar los objetos."
  type        = number
  default     = 365
}

variable "create_with_cloudformation" {
  description = "Crea el contenedor del bucket con CloudFormation (requerido en AWS Academy Learner Lab, cuya SCP impide a Terraform leer aws_s3_bucket)."
  type        = bool
  default     = false
}
