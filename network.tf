############################################
# VPC y subredes
############################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # La IP pública se asigna de forma explícita en la instancia; la subred no la
  # entrega por defecto para evitar exposición accidental de nuevos recursos.
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

############################################
# Grupo de seguridad por defecto bloqueado (CIS AWS 5.4)
############################################
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # Sin bloques ingress/egress: Terraform elimina todas las reglas por defecto.
  tags = { Name = "${local.name_prefix}-default-sg-locked" }
}

############################################
# VPC Flow Logs (CIS AWS 3.9)
############################################
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/${var.project_name}/${var.environment}/network/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_iam_role" "flow_logs" {
  count = var.use_lab_role ? 0 : 1

  name                 = "${local.name_prefix}-vpc-flow-logs"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:vpc-flow-log/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.use_lab_role ? 0 : 1

  name = "write-flow-logs"
  role = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteOnlyToFlowLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id       = aws_vpc.main.id
  traffic_type = "ALL"
  # Learner Lab: LabRole no admite a vpc-flow-logs.amazonaws.com, por lo que el destino
  # pasa a S3 (entrega directa del servicio, sin rol). Cuenta propia: CloudWatch Logs.
  log_destination_type     = var.use_lab_role ? "s3" : "cloud-watch-logs"
  log_destination          = var.use_lab_role ? "${module.access_logs_bucket.arn}/vpc-flow-logs/" : aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = var.use_lab_role ? null : aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = { Name = "${local.name_prefix}-vpc-flow-log" }
}
