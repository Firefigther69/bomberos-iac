############################################
# Módulo: bucket S3 endurecido
#
# Aplica en un único lugar los controles que comparten todos los buckets del
# proyecto: bloqueo de acceso público, propiedad de objetos forzada, cifrado
# por defecto, versionado, ciclo de vida, registro de accesos y denegación
# de tráfico sin TLS.
############################################
resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV2_AWS_62:Sin consumidores de eventos de objetos; la trazabilidad de escrituras se cubre con eventos de datos de CloudTrail
  #checkov:skip=CKV_AWS_144:Replicación entre regiones fuera del alcance de costo del ambiente académico; versionado y ciclo de vida activos
  count = var.create_with_cloudformation ? 0 : 1

  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = { Name = var.bucket_name, Purpose = var.purpose }
}

moved {
  from = aws_s3_bucket.this
  to   = aws_s3_bucket.this[0]
}

# AWS Academy Learner Lab: una política de control de servicio (SCP) niega
# s3:GetBucketObjectLockConfiguration, que el proveedor de Terraform invoca al leer
# cualquier aws_s3_bucket. En ese caso el bucket (solo el contenedor) se declara con
# CloudFormation desde Terraform; todos sus controles se siguen gestionando abajo.
resource "aws_cloudformation_stack" "bucket" {
  count = var.create_with_cloudformation ? 1 : 0

  name = "${var.bucket_name}-stack"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Contenedor S3 ${var.purpose}; controles gestionados por Terraform"
    Resources = {
      Bucket = {
        Type           = "AWS::S3::Bucket"
        DeletionPolicy = "Delete"
        Properties = {
          BucketName = var.bucket_name
          Tags = [
            { Key = "Name", Value = var.bucket_name },
            { Key = "Purpose", Value = var.purpose },
          ]
        }
      }
    }
    Outputs = {
      BucketName = { Value = { Ref = "Bucket" } }
    }
  })
}

locals {
  bucket_id  = var.create_with_cloudformation ? aws_cloudformation_stack.bucket[0].outputs["BucketName"] : aws_s3_bucket.this[0].id
  bucket_arn = "arn:aws:s3:::${local.bucket_id}"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = local.bucket_id

  rule {
    # Desactiva ACL: el acceso se controla solo con políticas IAM y de bucket.
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = local.bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = local.bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = local.bucket_id

  rule {
    id     = "retencion-y-archivado"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.enable_access_logging ? 1 : 0

  bucket        = local.bucket_id
  target_bucket = var.access_log_bucket_id
  target_prefix = "${var.bucket_name}/"
}

data "aws_iam_policy_document" "this" {
  source_policy_documents = var.additional_policy_json == null ? [] : [var.additional_policy_json]

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyOutdatedTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = local.bucket_id
  policy = data.aws_iam_policy_document.this.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
