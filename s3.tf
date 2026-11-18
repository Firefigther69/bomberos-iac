locals {
  trail_name        = "${local.name_prefix}-trail"
  trail_arn         = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  bucket_access_log = "${local.name_prefix}-access-logs-${local.account_id}"
  bucket_trail      = "${local.name_prefix}-cloudtrail-${local.account_id}"
  bucket_artifacts  = "${local.name_prefix}-artifacts-${local.account_id}"
}

############################################
# Bucket de registros de acceso del servidor (S3 Server Access Logging)
# Usa SSE-S3 porque el servicio de registro de S3 no admite destinos con SSE-KMS.
############################################
data "aws_iam_policy_document" "access_logs_bucket" {
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${local.bucket_access_log}/vpc-flow-logs/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${local.partition}:s3:::${local.bucket_access_log}"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowS3ServerAccessLogging"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${local.bucket_access_log}/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

module "access_logs_bucket" {
  source = "./modules/secure_bucket"

  create_with_cloudformation = var.use_lab_role

  bucket_name            = local.bucket_access_log
  purpose                = "s3-server-access-logs"
  kms_key_arn            = null
  force_destroy          = var.force_destroy_buckets
  additional_policy_json = data.aws_iam_policy_document.access_logs_bucket.json
  expiration_days        = 180
}

############################################
# Bucket de auditoría (CloudTrail)
############################################
data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${local.partition}:s3:::${local.bucket_trail}"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${local.bucket_trail}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # Protección de evidencia: nadie sin la etiqueta Role=audit-admin puede borrar
  # registros de auditoría. Se omite cuando force_destroy_buckets = true, porque
  # en un ambiente académico efímero `terraform destroy` debe poder vaciar el bucket.
  dynamic "statement" {
    for_each = var.force_destroy_buckets ? [] : [1]

    content {
      sid       = "DenyAuditLogDeletion"
      effect    = "Deny"
      actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
      resources = ["arn:${local.partition}:s3:::${local.bucket_trail}/AWSLogs/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "aws:PrincipalTag/Role"
        values   = ["audit-admin"]
      }
    }
  }
}

module "trail_bucket" {
  source = "./modules/secure_bucket"

  create_with_cloudformation = var.use_lab_role

  bucket_name            = local.bucket_trail
  purpose                = "cloudtrail-audit-logs"
  kms_key_arn            = aws_kms_key.main.arn
  force_destroy          = var.force_destroy_buckets
  enable_access_logging  = true
  access_log_bucket_id   = module.access_logs_bucket.id
  additional_policy_json = data.aws_iam_policy_document.trail_bucket.json
  transition_to_ia_days  = 90
  expiration_days        = 365
}

############################################
# Bucket de artefactos y reportes del pipeline
############################################
module "artifacts_bucket" {
  source = "./modules/secure_bucket"

  create_with_cloudformation = var.use_lab_role

  bucket_name           = local.bucket_artifacts
  purpose               = "codebuild-artifacts-and-reports"
  kms_key_arn           = aws_kms_key.main.arn
  force_destroy         = var.force_destroy_buckets
  enable_access_logging = true
  access_log_bucket_id  = module.access_logs_bucket.id
  transition_to_ia_days = 30
  expiration_days       = 90
}
