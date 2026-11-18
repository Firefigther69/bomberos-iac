############################################
# Identificación del proyecto
############################################
variable "project_name" {
  description = "Prefijo corto del proyecto. Se usa en nombres y etiquetas de todos los recursos."
  type        = string
  default     = "bomberos-la3"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name debe tener 3-21 caracteres: minúsculas, números y guiones, comenzando con letra."
  }
}

variable "environment" {
  description = "Ambiente de despliegue."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, qa, prod."
  }
}

variable "aws_region" {
  description = "Región AWS de despliegue."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Responsable técnico del despliegue (se registra como etiqueta Owner)."
  type        = string
  default     = "equipo-devops"
}

############################################
# Modalidad de cuenta
############################################
variable "use_lab_role" {
  description = <<-EOT
    true en AWS Academy Learner Lab: la cuenta no permite crear roles IAM, por lo que
    se reutilizan LabRole y LabInstanceProfile. false en una cuenta propia: se crean
    roles dedicados con políticas de mínimo privilegio.
  EOT
  type        = bool
  default     = false
}

############################################
# Red
############################################
variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un bloque CIDR IPv4 válido."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR de las subredes públicas (una por zona de disponibilidad)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Se requieren al menos dos CIDR válidos para distribuir en dos zonas de disponibilidad."
  }
}

variable "allowed_http_cidrs" {
  description = "Orígenes autorizados a consumir la aplicación por HTTP. Restringir a la red de la organización cuando sea posible."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_http_cidrs) > 0 && alltrue([for c in var.allowed_http_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_http_cidrs debe contener al menos un CIDR IPv4 válido."
  }
}

############################################
# Cómputo
############################################
variable "instance_type" {
  description = "Tipo de instancia EC2 del servidor de aplicación."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t3a?\\.(micro|small|medium)$", var.instance_type))
    error_message = "Por control de costos solo se permiten t3/t3a micro, small o medium."
  }
}

variable "root_volume_size" {
  description = "Tamaño en GiB del volumen raíz (gp3, cifrado)."
  type        = number
  default     = 10

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 50
    error_message = "root_volume_size debe estar entre 8 y 50 GiB."
  }
}

variable "enable_auto_recovery" {
  description = "Asocia la acción de recuperación automática de EC2 a la alarma de falla de sistema."
  type        = bool
  default     = true
}

############################################
# Observabilidad
############################################
variable "log_retention_days" {
  description = "Días de retención de los grupos de logs de CloudWatch (mínimo recomendado: 1 año)."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days debe ser un valor aceptado por CloudWatch Logs."
  }
}

variable "alarm_email" {
  description = "Correo que recibe las notificaciones de alarmas. Vacío para no crear la suscripción."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email debe ser un correo válido o una cadena vacía."
  }
}

variable "cpu_alarm_threshold" {
  description = "Umbral (%) de utilización de CPU que dispara la alarma."
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "Umbral (%) de uso de memoria que dispara la alarma."
  type        = number
  default     = 85
}

variable "disk_alarm_threshold" {
  description = "Umbral (%) de uso del disco raíz que dispara la alarma."
  type        = number
  default     = 80
}

variable "http_5xx_threshold" {
  description = "Cantidad de respuestas HTTP 5xx en 5 minutos que dispara la alarma."
  type        = number
  default     = 5
}

variable "latency_threshold_seconds" {
  description = "Tiempo de respuesta promedio (segundos) que dispara la alarma de latencia."
  type        = number
  default     = 2
}

############################################
# Auditoría
############################################
variable "enable_cloudtrail" {
  description = "Crea el trail multi-región con validación de integridad y envío a CloudWatch Logs."
  type        = bool
  default     = true
}

variable "cloudtrail_to_cloudwatch" {
  description = "Envía los eventos de CloudTrail a CloudWatch Logs (requerido por las alarmas de seguridad). Desactivar solo si la cuenta impide asociar el rol."
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Permite destruir buckets con objetos. Usar true solo en ambientes académicos efímeros."
  type        = bool
  default     = false
}

############################################
# CI/CD
############################################
variable "repository_url" {
  description = "URL HTTPS del repositorio Git (GitHub) que CodeBuild clona."
  type        = string
  default     = "https://github.com/Firefigther69/bomberos-iac.git"

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/[^/]+(\\.git)?$", var.repository_url))
    error_message = "repository_url debe ser una URL HTTPS de GitHub."
  }
}

variable "repository_branch" {
  description = "Rama que construye CodeBuild."
  type        = string
  default     = "main"
}

variable "terraform_version" {
  description = "Versión de Terraform instalada en CodeBuild (mantener alineada con versions.tf)."
  type        = string
  default     = "1.12.2"
}

variable "integration_test_schedule" {
  description = "Expresión de EventBridge para ejecutar las pruebas de integración de forma periódica. Vacío para desactivar."
  type        = string
  default     = "cron(0 11 * * ? *)"
}

variable "enable_github_webhook" {
  description = <<-EOT
    Crea el webhook que ejecuta CodeBuild validate en cada push y pull request.
    Requiere conectar GitHub en la consola de CodeBuild (credencial de origen) antes del apply.
  EOT
  type        = bool
  default     = false
}

variable "enable_codebuild" {
  description = <<-EOT
    Crea los proyectos CodeBuild del pipeline. En AWS Academy Learner Lab debe ser false:
    LabRole no admite a codebuild.amazonaws.com como entidad de confianza y la cuenta no
    permite crear roles. En ese caso la validación se ejecuta en GitHub Actions y las
    pruebas de integración con scripts/deploy.sh.
  EOT
  type        = bool
  default     = true
}
