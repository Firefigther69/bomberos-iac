############################################
# Identidades del proyecto
#
# Cuenta propia (use_lab_role = false): un rol por función, con políticas
# en línea acotadas a los ARN concretos que crea este proyecto. No se usan
# políticas administradas amplias (AdministratorAccess, *FullAccess).
#
# AWS Academy (use_lab_role = true): la cuenta prohíbe crear roles, por lo que
# se reutiliza LabRole. Esta limitación queda documentada como riesgo aceptado.
############################################
data "aws_iam_role" "lab" {
  count = var.use_lab_role ? 1 : 0
  name  = "LabRole"
}

data "aws_iam_instance_profile" "lab" {
  count = var.use_lab_role ? 1 : 0
  name  = "LabInstanceProfile"
}

locals {
  ec2_instance_profile_name = var.use_lab_role ? data.aws_iam_instance_profile.lab[0].name : aws_iam_instance_profile.ec2[0].name
  codebuild_role_arn        = var.use_lab_role ? data.aws_iam_role.lab[0].arn : aws_iam_role.codebuild[0].arn
  events_role_arn           = var.use_lab_role ? data.aws_iam_role.lab[0].arn : (var.enable_codebuild ? aws_iam_role.events[0].arn : null)
  cloudtrail_logs_role_arn  = var.use_lab_role ? data.aws_iam_role.lab[0].arn : aws_iam_role.cloudtrail_logs[0].arn

  app_log_group_arns = [for k, lg in aws_cloudwatch_log_group.app : lg.arn]
}

############################################
# Rol de la instancia EC2
############################################
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  count = var.use_lab_role ? 0 : 1

  name                 = "${local.name_prefix}-ec2-app"
  description          = "Servidor web: logs y metricas propias, lectura de su configuracion y Session Manager"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ec2" {
  #checkov:skip=CKV_AWS_111:Recurso * solo en acciones sin soporte de nivel de recurso (PutMetricData acotado por namespace, canal SSM)
  #checkov:skip=CKV_AWS_356:Idem; acciones Describe* y ssmmessages/ec2messages no admiten ARN
  statement {
    sid    = "WriteOwnLogGroups"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [for arn in local.app_log_group_arns : "${arn}:*"]
  }

  statement {
    sid       = "PutMetricsOnlyInProjectNamespace"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # La acción no admite restricción por recurso.

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.metrics_namespace_ec2]
    }
  }

  statement {
    sid    = "AgentMetadataDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
    ]
    resources = ["*"] # Acciones Describe* sin soporte de nivel de recurso.
  }

  statement {
    sid       = "ReadOwnConfiguration"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${local.ssm_prefix}/*"]
  }

  statement {
    sid       = "DecryptSecureParametersViaSSMOnly"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }

  # Mínimo requerido por el agente SSM para Session Manager y Run Command.
  # Reemplaza a la política administrada AmazonSSMManagedInstanceCore, que
  # además concede ssm:GetParameter(s) sobre cualquier parámetro de la cuenta.
  statement {
    sid    = "SessionManagerCore"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"] # Acciones del canal de control del agente sin soporte de nivel de recurso.
  }
}

resource "aws_iam_role_policy" "ec2" {
  count = var.use_lab_role ? 0 : 1

  name   = "least-privilege-app"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.ec2.json
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.use_lab_role ? 0 : 1

  name = "${local.name_prefix}-ec2-app"
  role = aws_iam_role.ec2[0].name
}

############################################
# Rol de CodeBuild
############################################
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  count = var.use_lab_role ? 0 : 1

  name                 = "${local.name_prefix}-codebuild"
  description          = "Pipeline: validacion estatica y pruebas de integracion de solo lectura"
  assume_role_policy   = data.aws_iam_policy_document.codebuild_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "codebuild" {
  #checkov:skip=CKV_AWS_356:Acciones de lectura Describe*/Get* sin soporte de nivel de recurso usadas por las pruebas de integración
  statement {
    sid       = "WriteBuildLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }

  statement {
    sid    = "ArtifactsReadWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketLocation",
    ]
    resources = [
      module.artifacts_bucket.arn,
      "${module.artifacts_bucket.arn}/*",
    ]
  }

  statement {
    sid       = "UseProjectKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid    = "PublishTestReports"
    effect = "Allow"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:BatchPutCodeCoverages",
    ]
    resources = ["arn:${local.partition}:codebuild:${local.region}:${local.account_id}:report-group/${local.name_prefix}-*"]
  }

  # Las pruebas de integración solo leen el estado real de la infraestructura.
  statement {
    sid    = "IntegrationTestsReadOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeVolumes",
      "ec2:DescribeFlowLogs",
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:GetEventSelectors",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetDashboard",
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics",
      "logs:DescribeLogGroups",
      "logs:DescribeMetricFilters",
      "sns:GetTopicAttributes",
      "kms:GetKeyRotationStatus",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"] # Acciones de lectura sin soporte de nivel de recurso.
  }

  statement {
    sid    = "IntegrationTestsReadBuckets"
    effect = "Allow"
    actions = [
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketVersioning",
      "s3:GetBucketPolicy",
      "s3:GetBucketLogging",
    ]
    resources = [
      module.trail_bucket.arn,
      module.artifacts_bucket.arn,
      module.access_logs_bucket.arn,
    ]
  }

  statement {
    sid       = "IntegrationTestsReadOwnParameterMetadata"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  count = var.use_lab_role ? 0 : 1

  name   = "least-privilege-pipeline"
  role   = aws_iam_role.codebuild[0].id
  policy = data.aws_iam_policy_document.codebuild.json
}

############################################
# Rol de EventBridge (ejecución programada de pruebas de integración)
############################################
resource "aws_iam_role" "events" {
  count = !var.use_lab_role && var.enable_codebuild ? 1 : 0

  name                 = "${local.name_prefix}-events-start-build"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "events" {
  count = !var.use_lab_role && var.enable_codebuild ? 1 : 0

  name = "start-integration-build-only"
  role = aws_iam_role.events[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartOnlyIntegrationProject"
      Effect   = "Allow"
      Action   = "codebuild:StartBuild"
      Resource = aws_codebuild_project.integration[0].arn
    }]
  })
}

############################################
# Rol de CloudTrail para entregar eventos a CloudWatch Logs
############################################
resource "aws_iam_role" "cloudtrail_logs" {
  count = var.use_lab_role ? 0 : 1

  name                 = "${local.name_prefix}-cloudtrail-to-cwlogs"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  count = var.use_lab_role ? 0 : 1

  name = "write-trail-log-group"
  role = aws_iam_role.cloudtrail_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteOnlyTrailLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

############################################
# Política de contraseñas de la cuenta (CIS AWS 1.8 - 1.9)
############################################
resource "aws_iam_account_password_policy" "strict" {
  count = var.use_lab_role ? 0 : 1

  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}
